import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todart_txt/features/tasks/gatefile_storage.dart';
import 'package:todart_txt/features/tasks/task_list_page.dart';
import 'package:todart_txt/features/tasks/task_repository.dart';

/// In-memory gatefile backend: no sockets (widget tests stub HTTP).
class CountingGatefileStorage extends GatefileTodoStorage {
  int reads = 0;
  CountingGatefileStorage()
      : super(Uri.parse('http://127.0.0.1:1/gatefile/todo.txt'), 'k');

  @override
  Future<String> readAll() async {
    reads++;
    return 'plain task\n';
  }

  @override
  Future<void> writeAll(String text) async {}
}

void main() {
  testWidgets('resume does not re-GET gatefile backend (SSE covers it)',
      (tester) async {
    final storage = CountingGatefileStorage();
    final repo = TaskRepository();
    await tester.runAsync(() async {
      await repo.loadFromStorage(storage);
    });
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
        MaterialApp(home: TaskListPage(repository: repo)));
    await tester.pump(const Duration(milliseconds: 100));
    final base = storage.reads;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 100));
    await tester
        .runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(milliseconds: 100));
    // Focusing the window to edit must not cost a GET.
    expect(storage.reads, base);
  });
}
