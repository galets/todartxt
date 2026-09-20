import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:todo_txt/todo_txt.dart';
import 'package:todart_txt/features/tasks/task_repository.dart';

void main() {
  group('resolveTodoPath', () {
    test('returns first arg', () {
      expect(resolveTodoPath(['/tmp/todo.txt']), '/tmp/todo.txt');
    });

    test('returns empty string when no args and no local todo.txt', () {
      expect(resolveTodoPath([], exists: (_) => false), '');
    });

    test('uses todo.txt from current directory when no args', () {
      expect(resolveTodoPath([], exists: (_) => true), 'todo.txt');
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

    Future<List<Task>> readTasks(String path) => TodoTxt.load(
          File(path).openRead().transform(utf8.decoder).transform(const LineSplitter()),
        );

    test('loads tasks from file supplied on command line', () async {
      final path = writeTodo('todo.txt', '(A) Call mom +Family @phone\nBuy milk\n');
      final repo = TaskRepository();
      await repo.load(path);
      expect(repo.path, path);
      expect(repo.tasks.map((t) => t.title), ['Call mom', 'Buy milk']);
      expect(repo.tasks.first.priority, 'A');
    });

    test('toggle + save persists to loaded file', () async {
      final path = writeTodo('todo.txt', 'Buy milk\n');
      final repo = TaskRepository();
      await repo.load(path);
      await repo.toggleCompleted(0);
      final reloaded = await readTasks(path);
      expect(reloaded.first.completed, isTrue);
    });

    test('add/update/remove persist to loaded file', () async {
      final path = writeTodo('todo.txt', 'Buy milk\n');
      final repo = TaskRepository();
      await repo.load(path);
      await repo.add(Task.fromText('(B) Walk dog'));
      await repo.update(0, Task.fromText('Buy bread'));
      await repo.removeAt(1);
      final reloaded = await readTasks(path);
      expect(reloaded.map((t) => t.title), ['Buy bread']);
    });

    test('save without load throws', () {
      expect(() => TaskRepository().save(), throwsStateError);
    });
  });
}
