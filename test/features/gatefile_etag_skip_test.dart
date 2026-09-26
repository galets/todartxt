import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:todart_txt/features/tasks/todo_storage.dart';

void main() {
  test('SSE event matching held ETag is skipped', () async {
    const etag = 'abc123';
    final server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      if (req.uri.query.contains('subscribe')) {
        req.response.headers.contentType =
            ContentType.parse('text/event-stream');
        req.response.write('$etag\n\n');
        // Keep open briefly so client can read, then close.
        await req.response.flush();
        await Future.delayed(const Duration(milliseconds: 300));
        await req.response.close();
        return;
      }
      req.response.headers.set('ETag', etag);
      req.response.write('a\n');
      await req.response.close();
    });
    final s = GatefileTodoStorage(
      Uri.parse('http://127.0.0.1:${server.port}/gatefile/todo.txt'),
      'k',
    );
    expect(await s.readAll(), 'a\n');
    var events = 0;
    final sub = s.updated.listen((_) => events++);
    await Future.delayed(const Duration(seconds: 2));
    await sub.cancel();
    s.close();
    await server.close(force: true);
    // Matching echo must not surface as an update.
    expect(events, 0);
  });

  test('save is PUT-only, no refresh GET', () async {
    var gets = 0;
    final server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      if (req.method == 'POST') {
        await req.drain();
        req.response.headers.set('ETag', 'new-etag');
        req.response.statusCode = 200;
        await req.response.close();
        return;
      }
      if (req.uri.query.contains('subscribe')) {
        req.response.headers.contentType =
            ContentType.parse('text/event-stream');
        await req.response.close();
        return;
      }
      gets++;
      req.response.headers.set('ETag', 'old-etag');
      req.response.write('a\n');
      await req.response.close();
    });
    final s = GatefileTodoStorage(
      Uri.parse('http://127.0.0.1:${server.port}/gatefile/todo.txt'),
      'k',
    );
    await s.readAll();
    expect(gets, 1);
    await s.writeAll('b\n');
    expect(gets, 1);
    s.close();
    await server.close(force: true);
  });
}
