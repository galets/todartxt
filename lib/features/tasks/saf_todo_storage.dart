import 'dart:convert';

import 'todo_storage.dart';

/// SAF document backend: addresses a single `content://` document URI.
///
/// All platform calls are injected so unit tests and Linux builds never
/// touch `package:saf` (Android-only). The thin wiring to the real `Saf()`
/// plugin (pickers + `readFileBytes`/`writeFileBytes`/stat) lands in slice 3
/// (`saf_bindings.dart`); this class is the testable transport seam.
///
/// [readBytes]/[writeBytes]/[statMtime] throw on offline / revoked grant;
/// [isReachable] returns false instead of throwing in those cases.
class SafTodoStorage implements TodoStorage {
  final String uri;

  final Future<String> Function(String uri) _readBytes;
  final Future<void> Function(String uri, String text) _writeBytes;
  final Future<DateTime?> Function(String uri)? _statMtime;

  SafTodoStorage(
    this.uri, {
    required Future<String> Function(String uri) readBytes,
    required Future<void> Function(String uri, String text) writeBytes,
    Future<DateTime?> Function(String uri)? statMtime,
  })  : _readBytes = readBytes,
        _writeBytes = writeBytes,
        _statMtime = statMtime;

  @override
  String get displayName => uri;

  @override
  Future<bool> isReachable() async {
    try {
      await _readBytes(uri);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<DateTime?> lastModified() async {
    final stat = _statMtime;
    if (stat == null) return null;
    try {
      return await stat(uri);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String> readAll() => _readBytes(uri);

  @override
  Future<void> writeAll(String text) => _writeBytes(uri, text);
}

/// Local mirror of a SAF document for offline use (doc §2).
///
/// Layout under `<app docs>/saf-mirror/`:
/// * `todo.txt` — last known good remote content (or offline edits).
/// * `meta.json` — `uri`, `lastSync` (ISO8601), `lastKnownRemoteMtime`
///   (ISO8601, nullable), `dirty` (bool).
class MirrorCache {
  final String dirPath;
  final Future<String> Function(String path) readFile;
  final Future<void> Function(String path, String text) writeFile;

  MirrorCache(
    this.dirPath, {
    required this.readFile,
    required this.writeFile,
  });

  String get todoPath => '$dirPath/todo.txt';
  String get metaPath => '$dirPath/meta.json';

  /// Cached content, or null when no mirror exists yet.
  Future<String?> loadMirror() async {
    try {
      return await readFile(todoPath);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> loadMeta() async {
    try {
      final raw = await readFile(metaPath);
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Overwrite mirror + meta after a successful remote read/write.
  Future<void> refreshMirror({
    required String uri,
    required String text,
    DateTime? remoteMtime,
  }) async {
    final now = DateTime.now();
    await writeFile(todoPath, text);
    await writeFile(
      metaPath,
      jsonEncode({
        'uri': uri,
        'lastSync': now.toIso8601String(),
        'lastKnownRemoteMtime': remoteMtime?.toIso8601String(),
        'dirty': false,
      }),
    );
  }

  /// Buffer an offline edit: update mirror content, keep last-sync, set dirty.
  Future<void> markDirty(String text) async {
    final meta =
        await loadMeta() ?? {'uri': '', 'lastSync': null, 'dirty': false};
    meta['dirty'] = true;
    await writeFile(todoPath, text);
    await writeFile(metaPath, jsonEncode(meta));
  }

  Future<bool> isDirty() async {
    final meta = await loadMeta();
    return meta?['dirty'] == true;
  }

  Future<void> clearDirty() async {
    final meta = await loadMeta();
    if (meta == null) return;
    meta['dirty'] = false;
    await writeFile(metaPath, jsonEncode(meta));
  }
}
