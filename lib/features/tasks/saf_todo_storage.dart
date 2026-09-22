import 'todo_storage.dart';

/// SAF document backend: addresses a single `content://` document URI.
///
/// All platform calls are injected so unit tests and Linux builds never
/// touch `package:saf` (Android-only). The thin wiring to the real `Saf()`
/// plugin (pickers + `readFileBytes`/`writeFileBytes`) lands in
/// (`saf_bindings.dart`); this class is the testable transport seam.
///
/// Always reads/writes the SAF document directly. No local cache:
/// failures propagate to callers.
class SafTodoStorage implements TodoStorage {
  final String uri;

  final Future<String> Function(String uri) _readBytes;
  final Future<void> Function(String uri, String text) _writeBytes;

  SafTodoStorage(
    this.uri, {
    required Future<String> Function(String uri) readBytes,
    required Future<void> Function(String uri, String text) writeBytes,
  })  : _readBytes = readBytes,
        _writeBytes = writeBytes;

  @override
  String get displayName => uri;

  @override
  Future<String> readAll() => _readBytes(uri);

  @override
  Future<void> writeAll(String text) => _writeBytes(uri, text);
}
