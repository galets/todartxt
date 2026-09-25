import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'todo_storage.dart';

/// Fatal config error: bad/missing API key. Never retry with same key.
class GatefileAuthException implements Exception {
  final String message;
  GatefileAuthException([this.message = 'Unauthorized (bad api_key)']);
  @override
  String toString() => 'GatefileAuthException: $message';
}

/// Stale-etag conflict that survived bounded rebases.
class GatefileConflictException implements Exception {
  final String message;
  GatefileConflictException([this.message = 'Conflict: stale ETag']);
  @override
  String toString() => 'GatefileConflictException: $message';
}

/// True for `gatefile://` / `gatefiles://` config values.
bool isGatefilePath(String path) =>
    path.startsWith('gatefile://') || path.startsWith('gatefiles://');

/// Map `gatefile(s)://host...` to `http(s)://host...` per doc/GATEFILE.md.
Uri gatefileEndpointUri(String path) {
  if (path.startsWith('gatefile://')) {
    return Uri.parse('http://${path.substring('gatefile://'.length)}');
  }
  if (path.startsWith('gatefiles://')) {
    return Uri.parse('https://${path.substring('gatefiles://'.length)}');
  }
  throw ArgumentError('Not a gatefile URI: $path');
}

/// Strip whitespace/CR, case-insensitive header lookup done by caller.
String normalizeEtag(String raw) => raw.trim().replaceAll('"', '');

const _maxRebase = 3;
const _maxPostAttempts = 5;

/// Gatefile backend: full-replace POST with optimistic concurrency.
///
/// Holds one [currentEtag] from last GET. Saves serialize through a
/// future chain so rapid edits never share one ETag. SSE via [watchEtags].
class GatefileTodoStorage implements TodoStorage {
  final Uri endpoint;
  final String apiKey;
  final HttpClient _client;
  final Duration sseBackoffMax;
  String? _currentEtag;
  Future<void> _queue = Future.value();
  bool _closed = false;

  GatefileTodoStorage(
    this.endpoint,
    this.apiKey, {
    HttpClient? client,
    this.sseBackoffMax = const Duration(seconds: 30),
  }) : _client = client ?? HttpClient();

  String? get currentEtag => _currentEtag;

  @override
  String get displayName => endpoint.toString();

  Map<String, String> get _auth => {'Authorization': 'Bearer $apiKey'};

  String _etagOf(HttpHeaders h) {
    var v = h.value('etag') ?? '';
    return normalizeEtag(v);
  }

  /// GET document. Updates [_currentEtag] on every 200.
  @override
  Future<String> readAll() async {
    final req = await _client.getUrl(endpoint);
    _auth.forEach(req.headers.add);
    final resp = await req.close();
    if (resp.statusCode == 401) {
      throw GatefileAuthException();
    }
    if (resp.statusCode != 200) {
      throw HttpException('GET failed: ${resp.statusCode}');
    }
    final body = await resp.transform(utf8.decoder).join();
    _currentEtag = _etagOf(resp.headers);
    return body;
  }

  /// POST full body with `If-Match: currentEtag`.
  /// On 200 adopts the response ETag (no re-GET).
  /// Handles 409 (rebase retry), 423/5xx (backoff retry), 401 (fatal).
  @override
  Future<void> writeAll(String text) {
    // Serialize saves: edit2 waits for edit1 POST (new ETag).
    final next = _queue.then((_) => _postLocked(text));
    _queue = next.catchError((_) {});
    return next;
  }

  Future<void> _postLocked(String text) async {
    var rebases = 0;
    // ignore: unused_local_variable
    var pending = text;
    while (true) {
      var etag = _currentEtag;
      if (etag == null || etag.isEmpty) {
        // Never POST without ETag: fetch first.
        await readAll();
        etag = _currentEtag;
        rebases++;
        if (rebases > _maxRebase) {
          throw GatefileConflictException();
        }
        continue;
      }
      final outcome = await _tryPost(etag, pending);
      if (outcome.result == _PostResult.ok) {
        // POST 200: adopt new ETag, no refresh GET. The server sends
        // no ETag header, so derive it as md5 of the written body
        // (server ETag scheme). A hook rewrite would broadcast a
        // different ETag, converging via SSE.
        _currentEtag =
            outcome.etag.isEmpty ? _md5Hex(pending) : outcome.etag;
        return;
      }
      if (outcome.result == _PostResult.conflict) {
        rebases++;
        if (rebases > _maxRebase) {
          throw GatefileConflictException();
        }
        // Rebase: re-GET latest; re-apply intent = full replace
        // with latest known local text (caller queued newest text).
        await readAll();
        continue;
      }
      if (outcome.result == _PostResult.persisted) {
        // 500: doc persisted, no broadcast. Reconcile via GET.
        final body = await readAll();
        if (body == pending) {
          return;
        }
        rebases++;
        if (rebases > _maxRebase) {
          throw GatefileConflictException();
        }
        continue;
      }
      // retryable handled inside _tryPost with backoff; loop again.
    }
  }

  Future<_PostOutcome> _tryPost(String etag, String body) async {
    var attempt = 0;
    var delay = const Duration(milliseconds: 400);
    while (true) {
      attempt++;
      try {
        final req = await _client.postUrl(endpoint);
        _auth.forEach(req.headers.add);
        req.headers.set('If-Match', etag);
        req.headers.contentType = ContentType('text', 'plain');
        req.write(body);
        final resp = await req.close();
        final newEtag = _etagOf(resp.headers);
        await resp.drain();
        if (resp.statusCode == 200) {
          return _PostOutcome(_PostResult.ok, newEtag);
        }
        if (resp.statusCode == 401) {
          throw GatefileAuthException();
        }
        if (resp.statusCode == 409) {
          return const _PostOutcome(_PostResult.conflict, '');
        }
        if (resp.statusCode == 500) {
          return const _PostOutcome(_PostResult.persisted, '');
        }
        if (resp.statusCode == 423 || resp.statusCode >= 500) {
          // Same-ETag backoff retry, unless SSE invalidated etag.
          if (attempt >= _maxPostAttempts) {
            throw HttpException('POST failed: ${resp.statusCode}');
          }
          await Future.delayed(_jitter(delay));
          delay = _nextDelay(delay, const Duration(seconds: 5));
          continue;
        }
        if (resp.statusCode == 400) {
          // Client bug path: re-GET once then single retry.
          await readAll();
          if (attempt >= 2) {
            throw HttpException('POST 400');
          }
          continue;
        }
        throw HttpException('POST failed: ${resp.statusCode}');
      } on GatefileAuthException {
        rethrow;
      } catch (_) {
        if (attempt >= _maxPostAttempts) {
          rethrow;
        }
        await Future.delayed(_jitter(delay));
        delay = _nextDelay(delay, const Duration(seconds: 5));
      }
    }
  }

  /// SSE: GET `?subscribe`, emit non-empty `<etag>` tokens.
  /// First event is current ETag. Reconnects forever (except 401).
  /// Events matching the held [_currentEtag] are skipped (own echo
  /// or duplicate): only remote changes surface as updates.
  /// Uses a dedicated [HttpClient] so cancelling the subscription
  /// never blocks on the open stream (`async*` cancel would deadlock).
  Stream<String> watchEtags() {
    final ctrl = StreamController<String>();
    final sseClient = HttpClient();
    var done = false;
    ctrl.onCancel = () {
      done = true;
      sseClient.close(force: true);
    };
    () async {
      var delay = const Duration(seconds: 1);
      while (!done && !_closed) {
        try {
          final sub = endpoint.replace(
            query: endpoint.query.isEmpty
                ? 'subscribe'
                : '${endpoint.query}&subscribe',
          );
          final req = await sseClient.getUrl(sub);
          _auth.forEach(req.headers.add);
          req.headers.set('Accept', 'text/event-stream');
          final resp = await req.close();
          if (resp.statusCode == 401) {
            ctrl.addError(GatefileAuthException());
            break;
          }
          if (resp.statusCode != 200) {
            throw HttpException('subscribe: ${resp.statusCode}');
          }
          delay = const Duration(seconds: 1);
          var buf = '';
          await for (final chunk in resp.transform(utf8.decoder)) {
            if (done || _closed) {
              break;
            }
            buf += chunk;
            while (buf.contains('\n\n')) {
              final i = buf.indexOf('\n\n');
              final token = normalizeEtag(buf.substring(0, i));
              buf = buf.substring(i + 2);
              if (token.isNotEmpty && !done) {
                // Skip update when event matches held ETag.
                if (token != _currentEtag) {
                  ctrl.add(token);
                }
              }
            }
          }
        } on GatefileAuthException catch (e) {
          if (!ctrl.isClosed) {
            ctrl.addError(e);
          }
          break;
        } catch (_) {
          // Reconnect below.
        }
        if (done || _closed) {
          break;
        }
        await Future.delayed(_jitter(delay));
        delay = _nextDelay(delay, sseBackoffMax);
      }
      sseClient.close(force: true);
      if (!ctrl.isClosed) {
        await ctrl.close();
      }
    }();
    return ctrl.stream;
  }

  /// Close SSE loop + HTTP client.
  void close() {
    _closed = true;
    _client.close(force: true);
  }
}

/// Server ETag scheme: hex md5 of the document body.
String _md5Hex(String body) => md5.convert(utf8.encode(body)).toString();

enum _PostResult { ok, conflict, persisted }

/// POST outcome: result plus new ETag from the 200 response header.
class _PostOutcome {
  final _PostResult result;
  final String etag;
  const _PostOutcome(this.result, this.etag);
}

Duration _jitter(Duration d) {
  final ms = d.inMilliseconds;
  final j = (ms * (0.5 + Random().nextDouble() * 0.5)).round();
  return Duration(milliseconds: j);
}

Duration _nextDelay(Duration d, Duration cap) {
  final next = Duration(milliseconds: d.inMilliseconds * 2);
  return next > cap ? cap : next;
}
