import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:todart_txt/features/tasks/gatefile_storage.dart';

/// Integration vs real `gatefile` binary (must be on PATH).
/// Spawns server per test on 127.0.0.1:0? gatefile needs fixed port,
/// so pick a free one via ServerSocket probe.
void main() {
  group('gatefile mapping', () {
    test('scheme mapping', () {
      expect(
        gatefileEndpointUri('gatefile://127.0.0.1:8654/gatefile/todo.txt')
            .toString(),
        'http://127.0.0.1:8654/gatefile/todo.txt',
      );
      expect(
        gatefileEndpointUri('gatefiles://example.com/gatefile/todo.txt')
            .toString(),
        'https://example.com/gatefile/todo.txt',
      );
      expect(isGatefilePath('gatefile://h/p'), isTrue);
      expect(isGatefilePath('gatefiles://h/p'), isTrue);
      expect(isGatefilePath('/a/b.txt'), isFalse);
    });

    test('normalizeEtag strips quotes/CR', () {
      expect(normalizeEtag('  abc\r\n'), 'abc');
      expect(normalizeEtag('"abc"'), 'abc');
    });
  });

  group('gatefile live server', () {
    late Process proc;
    late Directory tmp;
    late Uri base;
    const apiKey = 'test-secret';

    Future<int> freePort() async {
      final s = await ServerSocket.bind('127.0.0.1', 0);
      final p = s.port;
      await s.close();
      return p;
    }

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('gatefile_test');
      final doc = File('${tmp.path}/todo.txt')..writeAsStringSync('a\n');
      final port = await freePort();
      base = Uri.parse('http://127.0.0.1:$port/gatefile/todo.txt');
      proc = await Process.start('gatefile', [], environment: {
        'ADDR': '127.0.0.1:$port',
        'BASE_URL': '/gatefile/todo.txt',
        'DOCUMENT_PATH': doc.path,
        'API_KEY': apiKey,
      });
      // Wait for readiness: poll GET.
      final client = HttpClient();
      for (var i = 0; i < 50; i++) {
        try {
          final req = await client.getUrl(base);
          req.headers.add('Authorization', 'Bearer $apiKey');
          final resp = await req.close().timeout(
            const Duration(milliseconds: 300),
          );
          await resp.drain();
          if (resp.statusCode == 200) {
            break;
          }
        } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 100));
      }
      client.close();
    });

    tearDown(() async {
      proc.kill(ProcessSignal.sigkill);
      await proc.exitCode.catchError((_) => -1);
      tmp.deleteSync(recursive: true);
    });

    test('read + write roundtrip with etag refresh', () async {
      final s = GatefileTodoStorage(base, apiKey);
      expect(await s.readAll(), 'a\n');
      final e1 = s.currentEtag;
      expect(e1, isNotNull);
      await s.writeAll('b\n');
      expect(await s.readAll(), 'b\n');
      expect(s.currentEtag, isNot(e1));
      s.close();
    });

    test('401 is fatal', () async {
      final s = GatefileTodoStorage(base, 'wrong');
      expect(s.readAll(), throwsA(isA<GatefileAuthException>()));
      s.close();
    });

    test('409 race: stale client rebases', () async {
      final a = GatefileTodoStorage(base, apiKey);
      final b = GatefileTodoStorage(base, apiKey);
      await a.readAll();
      await b.readAll();
      await a.writeAll('from-a\n');
      // b holds stale etag; writeAll must re-GET + retry, not throw.
      await b.writeAll('from-b\n');
      expect(await a.readAll(), 'from-b\n');
      a.close();
      b.close();
    });

    test('SSE skips own echo, emits only remote change', () async {
      final s = GatefileTodoStorage(base, apiKey);
      await s.readAll();
      final events = <String>[];
      final sub = s.watchEtags().listen(events.add);
      // Held ETag echo must be skipped: no event while idle.
      await Future.delayed(const Duration(seconds: 1));
      expect(events, isEmpty);
      // Remote change from another client must surface.
      final other = GatefileTodoStorage(base, apiKey);
      await other.readAll();
      await other.writeAll('sse-trigger\n');
      other.close();
      await _waitFor(() => events.isNotEmpty);
      expect(events.last, other.currentEtag);
      await sub.cancel();
      s.close();
    });
  });
}

Future<void> _waitFor(bool Function() cond) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!cond()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('timeout waiting for condition');
    }
    await Future.delayed(const Duration(milliseconds: 50));
  }
}
