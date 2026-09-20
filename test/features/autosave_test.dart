import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets('Ctrl+S triggers save', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final repo = await loadedRepo(tester);
    await tester.pumpWidget(MaterialApp(home: TaskListPage(repository: repo)));
    await settle(tester);
    final before = repo.saves;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await flush(tester);
    expect(repo.saves, greaterThan(before));
  });

  testWidgets('autosave on dispose persists unsaved changes', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final repo = await loadedRepo(tester);
    await tester.pumpWidget(MaterialApp(home: TaskListPage(repository: repo)));
    await settle(tester);
    await tester.runAsync(() async {
      repo.applyUnsaved((tasks) => tasks.add(Task.fromText('unsaved task')));
      expect(repo.isDirty, isTrue);
    });
    // Unmount page -> dispose should autosave.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await flush(tester);
    expect(repo.isDirty, isFalse);
    expect(File(repo.path!).readAsStringSync(), contains('unsaved task'));
  });

  test('saveIfDirty is no-op when clean', () async {
    final path = '${tmp.path}/todo.txt';
    File(path).writeAsStringSync('Buy milk\n');
    final repo = TaskRepository();
    await repo.load(path);
    expect(repo.isDirty, isFalse);
    await repo.saveIfDirty();
    expect(repo.isDirty, isFalse);
  });
}
