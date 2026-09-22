import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_txt/todo_txt.dart';
import 'package:todart_txt/features/tasks/task_list_page.dart';
import 'package:todart_txt/features/tasks/task_repository.dart';

class CountingRepo extends TaskRepository {
  int saves = 0;
  @override
  Future<void> save() async {
    saves++;
    await super.save();
  }
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('autosave'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<CountingRepo> loadedRepo(WidgetTester tester) async {
    late CountingRepo repo;
    await tester.runAsync(() async {
      final path = '${tmp.path}/todo.txt';
      File(path).writeAsStringSync('Buy milk\n');
      repo = CountingRepo();
      await repo.load(path);
    });
    return repo;
  }

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> flush(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
    }
    await t.pump(const Duration(milliseconds: 100));
  }

  test('every mutation saves immediately', () async {
    final path = '${tmp.path}/todo.txt';
    File(path).writeAsStringSync('Buy milk\n');
    final repo = CountingRepo();
    await repo.load(path);
    expect(repo.saves, 0);
    await repo.add(Task.fromText('Second task'));
    expect(repo.saves, 1);
    expect(File(path).readAsStringSync(), contains('Second task'));
    await repo.toggleCompleted(0);
    expect(repo.saves, 2);
    await repo.update(0, Task.fromText('Updated'));
    expect(repo.saves, 3);
    await repo.removeAt(1);
    expect(repo.saves, 4);
    await repo.undo();
    expect(repo.saves, 5);
  });

  testWidgets('no manual Save control exists', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final repo = await loadedRepo(tester);
    await tester.pumpWidget(MaterialApp(home: TaskListPage(repository: repo)));
    await settle(tester);
    expect(find.byTooltip('Save'), findsNothing);
    expect(find.byIcon(Icons.save), findsNothing);
    // Unmounting without edits triggers no save.
    final before = repo.saves;
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await flush(tester);
    expect(repo.saves, before);
  });
}
