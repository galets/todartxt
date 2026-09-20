import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todart_txt/features/tasks/storage_location.dart';

void main() {
  test('persisted shared folder wins over default', () async {
    SharedPreferences.setMockInitialValues({
      storageDirPrefsKey: '/storage/emulated/0/Tasks',
      storagePathPrefsKey: '/storage/emulated/0/Tasks/todo.txt',
    });
    final prefs = await SharedPreferences.getInstance();
    final path = await effectiveTodoPath([],
        platform: 'android', appDocDir: '/private/docs', prefs: prefs);
    expect(path, '/storage/emulated/0/Tasks/todo.txt');
  });

  test('android default without custom pick is shared Tasks (adb-visible)',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final path = await effectiveTodoPath([], platform: 'android', prefs: prefs);
    expect(path, '/storage/emulated/0/Tasks/todo.txt');
  });

  test('ensureSharedStorageAccess is injectable', () async {
    expect(
        await ensureSharedStorageAccess(
            platform: 'android', request: () async => true),
        isTrue);
    expect(
        await ensureSharedStorageAccess(
            platform: 'linux', request: () async => false),
        isTrue);
  });

  test('migrate copies content to shared storage path', () async {
    final tmp = await Directory.systemTemp.createTemp('safmig');
    try {
      final from = File('${tmp.path}/app/todo.txt');
      await from.parent.create(recursive: true);
      await from.writeAsString('call mom\n');
      final to = '${tmp.path}/shared/Tasks/todo.txt';
      await migrateTodoFile(from.path, to);
      expect(File(to).readAsStringSync(), 'call mom\n');
    } finally {
      tmp.deleteSync(recursive: true);
    }
  });
}
