import 'package:flutter_test/flutter_test.dart';
import 'package:todart_txt/features/tasks/saf_todo_storage.dart';

void main() {
  group('SafTodoStorage', () {
    test('read/write passthrough via injected SAF functions', () async {
      var contents = 'call mom\n';
      final s = SafTodoStorage(
        'content://drive/todo.txt',
        readBytes: (_) async => contents,
        writeBytes: (_, text) async {
          contents = text;
        },
      );
      expect(s.displayName, 'content://drive/todo.txt');
      expect(await s.readAll(), 'call mom\n');
      await s.writeAll('new\n');
      expect(contents, 'new\n');
      expect(await s.readAll(), 'new\n');
    });

    test('read/write errors propagate (no cache fallback)', () async {
      final s = SafTodoStorage(
        'content://drive/todo.txt',
        readBytes: (_) async => throw Exception('gone'),
        writeBytes: (_, __) async => throw Exception('gone'),
      );
      expect(() => s.readAll(), throwsA(isA<Exception>()));
      expect(() => s.writeAll('x'), throwsA(isA<Exception>()));
    });
  });
}
