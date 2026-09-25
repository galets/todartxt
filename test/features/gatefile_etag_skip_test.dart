import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:todart_txt/features/tasks/gatefile_storage.dart';

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
    await s.readAll();
    expect(s.currentEtag, etag);
    final events = <String>[];
    final sub = s.watchEtags().listen(events.add);
    await Future.delayed(const Duration(seconds: 2));
    await sub.cancel();
    s.close();
    await server.close(force: true);
    // Matching echo must not surface as an update.
    expect(events, isEmpty);
  });

  test('POST 200 ETag updates held ETag without re-GET', () async {
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
    // Held ETag comes from POST response; no refresh GET needed.
    expect(s.currentEtag, 'new-etag');
    expect(gets, 1);
    s.close();
    await server.close(force: true);
  });

  test('save mimics real server: POST without ETag, zero GETs', () async {
    // Real gatefile POST 200 has empty body and NO ETag header.
    var gets = 0;
    var content = 'a\n';
    final server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      if (req.method == 'POST') {
        final chunks = <List<int>>[];
        await for (final c in req) {
          chunks.add(c);
        }
        content = String.fromCharCodes(chunks.expand((e) => e));
        req.response.statusCode = 200;
        await req.response.close();
        return;
      }
      gets++;
      req.response.headers.set('ETag', 'md5-stub');
      req.response.write(content);
      await req.response.close();
    });
    final s = GatefileTodoStorage(
      Uri.parse('http://127.0.0.1:${server.port}/gatefile/todo.txt'),
      'k',
    );
    await s.readAll(); // startup GET
    final base = gets;
    await s.writeAll('b\n'); // edit + save: POST only
    // No refresh GET: ETag adopted locally as md5 of written body.
    expect(gets, base);
    expect(s.currentEtag, '3b5d5c3712955042212316173ccf37be');
    s.close();
    await server.close(force: true);
  });

}
