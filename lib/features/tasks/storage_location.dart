import 'dart:io';

import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'task_repository.dart';

const storagePathPrefsKey = 'todo_txt_custom_path';
const storageDirPrefsKey = 'todo_txt_custom_dir';

/// Effective todo.txt location.
///
/// Priority: explicit CLI arg > user-picked shared folder (SAF/picker,
/// persisted) > shared `/storage/emulated/0/Tasks/todo.txt` on Android
/// (visible to `adb ls`, file managers and sync apps; needs All-files
/// access, requested at startup) > platform default. App-private docs dir
/// is only a fallback when shared storage is unavailable.
Future<String> effectiveTodoPath(
  List<String> args, {
  String? platform,
  String? homeDir,
  String? appDocDir,
  Future<List<Directory?>?> Function()? externalDirs,
  SharedPreferences? prefs,
}) async {
  if (args.isNotEmpty) return args.first;
  try {
    final p = prefs ?? await SharedPreferences.getInstance();
    final custom = p.getString(storagePathPrefsKey);
    if (custom != null && custom.isNotEmpty) return custom;
    final dir = p.getString(storageDirPrefsKey);
    if (dir != null && dir.isNotEmpty) return '$dir/todo.txt';
  } catch (_) {
    // Fall through to platform default.
  }
  final isAndroid =
      platform != null ? platform == 'android' : Platform.isAndroid;
  if (isAndroid && appDocDir == null) {
    try {
      final root = await androidStorageRoot(externalDirs: externalDirs);
      return '$root/Tasks/todo.txt';
    } catch (_) {
      // Fall through.
    }
  }
  return defaultTodoPathAsync(
    platform: platform,
    homeDir: homeDir,
    appDocDir: appDocDir,
    externalDirs: externalDirs,
  );
}

/// Persist a user-picked shared folder (SAF tree) as `<dir>/todo.txt`.
Future<String> saveCustomDir(String dir, {SharedPreferences? prefs}) async {
  final path = '$dir/todo.txt';
  final p = prefs ?? await SharedPreferences.getInstance();
  await p.setString(storageDirPrefsKey, dir);
  await p.setString(storagePathPrefsKey, path);
  return path;
}

/// Copies todo.txt content from [fromPath] to [toPath] when migrating
/// between app-private and shared storage (no-op when equal or source missing).
Future<void> migrateTodoFile(String fromPath, String toPath) async {
  if (fromPath == toPath) return;
  final src = File(fromPath);
  if (!await src.exists()) return;
  final dst = File(toPath);
  await dst.parent.create(recursive: true);
  await src.copy(toPath);
}

/// Requests shared-storage write access on Android (All-files access on
/// API 30+, storage permission below). No-op on other platforms.
/// [request] is injectable for tests.
Future<bool> ensureSharedStorageAccess(
    {String? platform,
    Future<bool> Function()? request}) async {
  final isAndroid =
      platform != null ? platform == 'android' : Platform.isAndroid;
  if (!isAndroid) return true;
  if (request != null) return request();
  try {
    if (await Permission.manageExternalStorage.isGranted) return true;
    final status = await Permission.manageExternalStorage.request();
    if (status.isGranted) return true;
    // Pre-Android-11 fallback.
    if (await Permission.storage.isGranted) return true;
    return (await Permission.storage.request()).isGranted;
  } catch (_) {
    return false;
  }
}
