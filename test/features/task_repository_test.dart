import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:todo_txt/todo_txt.dart';
import 'package:todart_txt/features/tasks/task_repository.dart';

void main() {
  group('resolveTodoPath', () {
    test('returns first arg', () {
      expect(resolveTodoPath(['/tmp/todo.txt']), '/tmp/todo.txt');
    });

    test('returns empty string when no args', () {
      expect(resolveTodoPath([]), '');
    });
  });

  group('TaskRepository', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('todart_test');
    });

    tearDown(() {
      tmp.deleteSync(recursive: true);
    });

    String writeTodo(String name, String content) {
      final f = File('${tmp.path}/$name')..writeAsStringSync(content);
      return f.path;
    }

    test('loads tasks from file supplied on command line', () {
      final path = writeTodo('todo.txt', '(A) Call mom +Family @phone\nBuy milk\n');
      final repo = TaskRepository();
      repo.load(path);
      expect(repo.path, path);
      expect(repo.tasks.map((t) => t.title), ['Call mom', 'Buy milk']);
      expect(repo.tasks.first.priority, 'A');
    });

    test('toggle + save persists to loaded file', () {
      final path = writeTodo('todo.txt', 'Buy milk\n');
      final repo = TaskRepository()..load(path);
      repo.toggleCompleted(0);
      final reloaded = TodoTxt.readFromFile(path: path);
      expect(reloaded.tasks.first.completed, isTrue);
    });

    test('add/update/remove persist to loaded file', () {
      final path = writeTodo('todo.txt', 'Buy milk\n');
      final repo = TaskRepository()..load(path);
      repo.add(Task.fromText('(B) Walk dog'));
      repo.update(0, Task.fromText('Buy bread'));
      repo.removeAt(1);
      final reloaded = TodoTxt.readFromFile(path: path);
      expect(reloaded.tasks.map((t) => t.title), ['Buy bread']);
    });

    test('save without load throws', () {
      expect(() => TaskRepository().save(), throwsStateError);
    });
  });
}
