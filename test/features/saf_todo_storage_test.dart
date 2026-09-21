import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:todart_txt/features/tasks/saf_todo_storage.dart';

void main() {
  group('SafTodoStorage', () {
    test('read/write/stat passthrough via injected SAF functions', () async {
      var contents = 'call mom\n';
      var mtime = DateTime(2026, 9, 21, 12);
      final s = SafTodoStorage(
        'content://drive/todo.txt',
        readBytes: (_) async => contents,
        writeBytes: (_, text) async {
          contents = text;
          mtime = DateTime(2026, 9, 21, 13);
        },
        statMtime: (_) async => mtime,
      );
      expect(s.displayName, 'content://drive/todo.txt');
      expect(await s.readAll(), 'call mom\n');
      expect(await s.isReachable(), isTrue);
      expect(await s.lastModified(), mtime);
      await s.writeAll('new\n');
      expect(contents, 'new\n');
      expect(await s.lastModified(), DateTime(2026, 9, 21, 13));
    });

    test('isReachable false + lastModified null when provider gone', () async {
      Future<String> fail(String _) =>
          throw const FileSystemException('offline');
      Future<DateTime?> failStat(String _) =>
          throw const FileSystemException('offline');
      final s = SafTodoStorage(
        'content://drive/todo.txt',
        readBytes: fail,
        writeBytes: (uri, text) => fail(''),
        statMtime: failStat,
      );
      expect(await s.isReachable(), isFalse);
      expect(await s.lastModified(), isNull);
      expect(() => s.readAll(), throwsA(isA<FileSystemException>()));
      expect(() => s.writeAll('x'), throwsA(isA<FileSystemException>()));
    });

    test('lastModified null without stat callback (best-effort)', () async {
      final s = SafTodoStorage(
        'content://drive/todo.txt',
        readBytes: (_) async => '',
        writeBytes: (uri, text) async {},
      );
      expect(await s.lastModified(), isNull);
    });
  });

  group('MirrorCache', () {
    test('refresh → load roundtrip, dirty flag set/cleared', () async {
      final files = <String, String>{};
      final m = MirrorCache(
        '/docs/saf-mirror',
        readFile: (p) async {
          final v = files[p];
          if (v == null) throw const FileSystemException('missing');
          return v;
        },
        writeFile: (p, t) async => files[p] = t,
      );
      expect(await m.loadMirror(), isNull);
      expect(await m.isDirty(), isFalse);

      await m.refreshMirror(
        uri: 'content://drive/todo.txt',
        text: 'a\n',
        remoteMtime: DateTime(2026, 9, 21, 12),
      );
      expect(await m.loadMirror(), 'a\n');
      expect(await m.isDirty(), isFalse);

      await m.markDirty('a\nb\n');
      expect(await m.loadMirror(), 'a\nb\n');
      expect(await m.isDirty(), isTrue);

      await m.clearDirty();
      expect(await m.isDirty(), isFalse);
      // Offline edit preserved after clearing dirty.
      expect(await m.loadMirror(), 'a\nb\n');
    });
  });
}
