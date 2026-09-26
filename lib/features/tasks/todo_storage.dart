import 'dart:convert';
import 'dart:io';

import 'package:gatefile_dart/gatefile_dart.dart' as gf;

/// Storage backend seam for todo.txt content.
///
/// Linux + legacy local paths use [FileTodoStorage] (plain `dart:io`).
/// Android SAF document URIs use `SafTodoStorage` (via `package:saf`),
/// implementing this same interface so [TaskRepository] never touches
/// `content://` URIs directly. Backends always hit the underlying
/// document/file directly — no caching.
abstract class TodoStorage {
  /// Full todo.txt text.
  Future<String> readAll();

  /// Atomically replace full todo.txt text.
  Future<void> writeAll(String text);

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
    // Uses synchronous I/O so widget tests in fake-async zones complete
    // without requiring tester.runAsync for UI-triggered saves.
    var effectivePath = path;
    if (Link(path).existsSync()) {
      try {
        effectivePath = File(path).resolveSymbolicLinksSync();
      } on FileSystemException {
        // Dangling link or unresolvable: fall back to plain path.
      }
    }
    final f = File(effectivePath);
    f.parent.createSync(recursive: true);
    // Atomic replace: write temp then rename.
    final tmp = File('$effectivePath.tmp');
    tmp.writeAsStringSync(text, encoding: utf8);
    tmp.renameSync(effectivePath);
  }
}

/// Gatefile backend: [TodoStorage] bridge over `GatefileDocument`.
///
/// Pure delegation: [readAll] is `get`, [writeAll] is `put`
/// (throws [gf.Conflict] on stale write: re-`get`, merge, retry),
/// [updated] fires per remote change (call [readAll] to refresh).
class GatefileTodoStorage implements TodoStorage {
  final Uri endpoint;
  final String apiKey;
  final gf.GatefileDocument _doc;

  GatefileTodoStorage(this.endpoint, this.apiKey, {gf.GatefileDocument? doc})
      : _doc = doc ?? gf.GatefileDocument(baseUrl: endpoint, apiKey: apiKey);

  /// Fires per remote change (no payload). Call [readAll] to refresh.
  Stream<void> get updated => _doc.updated;

  @override
  String get displayName => endpoint.toString();

  @override
  Future<String> readAll() => _doc.get();

  @override
  Future<void> writeAll(String text) => _doc.put(text);

  /// Stop SSE + HTTP client.
  void close() {
    _doc.close();
  }
}

/// In-memory fake for unit/widget tests without touching the filesystem or SAF.
class FakeTodoStorage implements TodoStorage {
  String contents;
  final String label;
  int writes = 0;

  FakeTodoStorage(
    this.contents, {
    this.label = 'fake',
  });

  @override
  String get displayName => label;

  @override
  Future<String> readAll() async {
    return contents;
  }

  @override
  Future<void> writeAll(String text) async {
    contents = text;
    writes++;
  }
}
