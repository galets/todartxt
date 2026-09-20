import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:todart_txt/features/tasks/task_repository.dart';

void main() {
  test('android default path is app-private and writable (no shared storage)',
      () async {
    final appDoc = await Directory.systemTemp.createTemp('appdoc');
    try {
      final path = await defaultTodoPathAsync(
        platform: 'android',
        appDocDir: appDoc.path,
      );
      // Must live inside the app-private documents dir, not shared storage.
      expect(path.startsWith(appDoc.path), isTrue,
          reason: 'got $path, expected under ${appDoc.path}');
      expect(path.endsWith('todo.txt'), isTrue);
      // Must actually be creatable.
      final repo = TaskRepository();
      await repo.load(path);
      expect(File(path).existsSync(), isTrue);
    } finally {
      appDoc.deleteSync(recursive: true);
    }
  });
}
