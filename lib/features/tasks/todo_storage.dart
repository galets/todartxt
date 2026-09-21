import 'dart:convert';
import 'dart:io';

/// Storage backend seam for todo.txt content.
///
/// Linux + legacy local paths use [FileTodoStorage] (plain `dart:io`).
/// Android SAF document URIs will use `SafTodoStorage` (slice 2, via
/// `package:saf`), implementing this same interface so [TaskRepository]
/// never touches `content://` URIs directly.
abstract class TodoStorage {
  /// Full todo.txt text.
  Future<String> readAll();

  /// Atomically replace full todo.txt text.
  Future<void> writeAll(String text);

  /// Remote modification time, best-effort (null when unknown/offline).
  Future<DateTime?> lastModified();

  /// False when offline / provider gone (callers fall back to mirror).
  Future<bool> isReachable();

  /// Human-readable label for storage-location UI (path or URI).
  String get displayName;
}

/// Plain-filesystem backend: Linux + legacy local path. No new dependencies.
class FileTodoStorage implements TodoStorage {
  final String path;
  FileTodoStorage(this.path);

  @override
  String get displayName => path;

  @override
  Future<bool> isReachable() async => true;

  @override
  Future<DateTime?> lastModified() async {
    final f = File(path);
    if (!await f.exists()) return null;
    return (await f.stat()).modified;
  }

  @override
  Future<String> readAll() async {
    final f = File(path);
    if (!await f.exists()) {
      await f.parent.create(recursive: true);
      await f.writeAsString('');
      return '';
    }
    return f.readAsString();
  }

  @override
  Future<void> writeAll(String text) async {
    // Preserve symlinks: atomic rename would replace the link itself with
    // a regular file. Resolve to the link target so the linked file is updated.
    var effectivePath = path;
    if (await Link(path).exists()) {
      try {
        effectivePath = await File(path).resolveSymbolicLinks();
      } on FileSystemException {
        // Dangling link or unresolvable: fall back to plain path.
      }
    }
    final f = File(effectivePath);
    await f.parent.create(recursive: true);
    // Atomic replace: write temp then rename.
    final tmp = File('$effectivePath.tmp');
    await tmp.writeAsString(text, encoding: utf8);
    await tmp.rename(effectivePath);
  }
}

/// In-memory fake for unit/widget tests (conflict matrix, dirty-flag,
/// mirror fallback) without touching the filesystem or SAF.
class FakeTodoStorage implements TodoStorage {
  String contents;
  DateTime? mtime;
  bool reachable;
  final String label;
  int writes = 0;

  FakeTodoStorage(
    this.contents, {
    this.mtime,
    this.reachable = true,
    this.label = 'fake',
  });

  @override
  String get displayName => label;

  @override
  Future<bool> isReachable() async => reachable;

  @override
  Future<DateTime?> lastModified() async => mtime;

  @override
  Future<String> readAll() async {
    if (!reachable) throw const FileSystemException('offline');
    return contents;
  }

  @override
  Future<void> writeAll(String text) async {
    if (!reachable) throw const FileSystemException('offline');
    contents = text;
    mtime = DateTime.now();
    writes++;
  }
}
