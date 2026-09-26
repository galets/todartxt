import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gatefile_dart/gatefile_dart.dart' show AuthFailed, Conflict;
import 'package:todart_txt/features/tasks/storage_location.dart';
import 'package:todart_txt/features/tasks/todo_storage.dart';

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

    test('read + write roundtrip', () async {
      final s = GatefileTodoStorage(base, apiKey);
      expect(await s.readAll(), 'a\n');
      await s.writeAll('b\n');
      expect(await s.readAll(), 'b\n');
      s.close();
    });

    test('401 is fatal', () async {
      final s = GatefileTodoStorage(base, 'wrong');
      expect(s.readAll(), throwsA(isA<AuthFailed>()));
      s.close();
    });

    test('stale write throws Conflict; re-get + retry wins', () async {
      final a = GatefileTodoStorage(base, apiKey);
      final b = GatefileTodoStorage(base, apiKey);
      await a.readAll();
      await b.readAll();
      await a.writeAll('from-a\n');
      // b is stale: read-modify-write per library example.
      await expectLater(b.writeAll('from-b\n'), throwsA(isA<Conflict>()));
      await b.readAll();
      await b.writeAll('from-b\n');
      expect(await a.readAll(), 'from-b\n');
      a.close();
      b.close();
    });

    test('SSE skips own echo, emits only remote change', () async {
      final s = GatefileTodoStorage(base, apiKey);
      await s.readAll();
      var events = 0;
      final sub = s.updated.listen((_) => events++);
      // Held ETag echo must be skipped: no event while idle.
      await Future.delayed(const Duration(seconds: 1));
      expect(events, 0);
      // Remote change from another client must surface.
      final other = GatefileTodoStorage(base, apiKey);
      await other.readAll();
      await other.writeAll('sse-trigger\n');
      other.close();
      await _waitFor(() => events > 0);
      expect(await s.readAll(), 'sse-trigger\n');
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
