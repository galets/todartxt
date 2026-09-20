import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todart_txt/features/tasks/task_list_page.dart';
import 'package:todart_txt/features/tasks/task_repository.dart';
import 'package:todart_txt/main.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('todart_widget');
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  Future<TaskRepository> loadedRepo(String content) async {
    final path = '${tmp.path}/todo.txt';
    File(path).writeAsStringSync(content);
    final repo = TaskRepository();
    await repo.load(path);
    return repo;
  }

  testWidgets('shows error when no file supplied on command line',
      (tester) async {
    await tester.pumpWidget(const MyApp(todoPath: ''));
    expect(find.textContaining('No todo.txt file supplied'), findsOneWidget);
  });

  testWidgets('lists all tasks from loaded file', (tester) async {
    final repo = await loadedRepo('(A) Call mom +Family @phone\nBuy milk\n');
    await tester.pumpWidget(MaterialApp(home: TaskListPage(repository: repo)));
    expect(find.text('Call mom'), findsOneWidget);
    expect(find.text('Buy milk'), findsOneWidget);
    expect(find.byType(Checkbox), findsNWidgets(2));
  });

  testWidgets('toggling checkbox saves to file', (tester) async {
    final repo = await loadedRepo('Buy milk\n');
    await tester.pumpWidget(MaterialApp(home: TaskListPage(repository: repo)));
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(repo.tasks.first.completed, isTrue);
    expect(File(repo.path!).readAsStringSync(), contains('x '));
  });
}
