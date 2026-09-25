import 'dart:io';

import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'task_repository.dart';

const storagePathPrefsKey = 'todo_txt_custom_path';
const storageDirPrefsKey = 'todo_txt_custom_dir';
const safUriPrefsKey = 'todo_txt_saf_uri';
const gatefileApiKeyPrefsKey = 'todo_txt_gatefile_api_key';

/// Accept `http(s)://` or `gatefile(s)://`, return canonical
/// `gatefile(s)://` form. Returns null when invalid.
String? normalizeGatefileInput(String raw) {
  final v = raw.trim();
  if (v.isEmpty) {
    return null;
  }
  if (v.startsWith('gatefile://') || v.startsWith('gatefiles://')) {
    return v;
  }
  if (v.startsWith('http://')) {
    return 'gatefile://${v.substring('http://'.length)}';
  }
  if (v.startsWith('https://')) {
    return 'gatefiles://${v.substring('https://'.length)}';
  }
  return null;
}

/// Persist gatefile URL + API key. Returns canonical path.
Future<String> saveGatefileConfig(String url, String apiKey,
    {SharedPreferences? prefs}) async {
  final path = normalizeGatefileInput(url);
  if (path == null || path.isEmpty) {
    throw ArgumentError('Invalid gatefile URL: $url');
  }
  if (apiKey.isEmpty) {
    throw ArgumentError('Missing API key');
  }
  final p = prefs ?? await SharedPreferences.getInstance();
  await p.setString(storagePathPrefsKey, path);
  await p.setString(gatefileApiKeyPrefsKey, apiKey);
  return path;
}

/// Read persisted gatefile API key (Android GUI config).
Future<String?> readGatefileApiKey({SharedPreferences? prefs}) async {
  try {
    final p = prefs ?? await SharedPreferences.getInstance();
    final v = p.getString(gatefileApiKeyPrefsKey);
    if (v != null && v.isNotEmpty) {
      return v;
    }
    return null;
  } catch (_) {
    return null;
  }
}

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

/// True when [path] is a SAF document URI (`content://…`) rather than a
/// plain filesystem path. Such URIs must go through the SAF backend —
/// never `dart:io File` (which fails with `FileSystemException: Creation
/// failed … errno 30` on `content:` paths).
bool isSafUri(String path) => path.startsWith('content://');

/// Persist a user-picked todo.txt document URI (SAF `ACTION_OPEN_DOCUMENT`).
/// Unlike `ACTION_OPEN_DOCUMENT_TREE` (folder pick), every DocumentsProvider
/// — including ownCloud — supports file picking, so all providers stay
/// visible in the system picker.
Future<String> saveSafUri(String uri, {SharedPreferences? prefs}) async {
  final p = prefs ?? await SharedPreferences.getInstance();
  await p.setString(safUriPrefsKey, uri);
  await p.setString(storagePathPrefsKey, uri);
  return uri;
}

/// Persist a user-picked shared folder (SAF tree) as `<dir>/todo.txt`.
/// Legacy local-folder path; prefer [saveSafUri] on Android since
/// `ACTION_OPEN_DOCUMENT_TREE` hides providers without tree support
/// (e.g. ownCloud).
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
