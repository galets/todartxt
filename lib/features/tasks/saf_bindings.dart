import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:saf/saf.dart';

import 'saf_todo_storage.dart';

/// Real Android wiring for [SafTodoStorage] via `package:saf` (v2 API).
///
/// Uses `ACTION_OPEN_DOCUMENT` (file pick), which every `DocumentsProvider`
/// (including ownCloud) supports, instead of `ACTION_OPEN_DOCUMENT_TREE`,
/// which ownCloud does not advertise — that is why ownCloud was missing
/// from the old folder picker.
///
/// Read: `readFileBytes(uri)` → UTF-8.
/// Write: write bytes directly to the already-open `wt` file descriptor
///   number (POSIX `write`), then the plugin closes it to commit. Never
///   re-open `/proc/self/fd/<fd>` via `File`: on network-backed providers
///   (ownCloud) that re-open loses the stream and leaves a 0-byte file.
/// Stat: `stat(uri).modified`.
///
/// Injectable [rawWrite] exists so tests can verify descriptor writes
/// without touching libc.
SafTodoStorage safStorageForUri(String uri, [Saf? saf]) {
  final s = saf ?? Saf();
  return SafTodoStorage(
    uri,
    readBytes: (u) async => utf8.decode(await s.readFileBytes(u)),
    writeBytes: (u, text) async {
      await s.withFileDescriptor(u, 'wt', (fd) async {
        await writeToFd(fd.fd, utf8.encode(text));
      });
    },
    statMtime: (u) async {
      final info = await s.stat(u);
      if (info == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(info.lastModified);
    },
  );
}

/// Writes [bytes] to already-open file descriptor [fd] via libc `write`.
///
/// Loops on partial writes; throws [IOException] on error.
Future<void> writeToFd(
  int fd,
  List<int> bytes, {
  int Function(int fd, Pointer<Uint8> buf, int count)? rawWrite,
}) async {
  final write = rawWrite ?? _libcWrite;
  final data = Uint8List.fromList(bytes);
  if (data.isEmpty) return;
  // Empty content: nothing to write; closing the `wt` fd commits truncate.
  final ptr = calloc<Uint8>(data.length);
  try {
    ptr.asTypedList(data.length).setAll(0, data);
    var offset = 0;
    while (offset < data.length) {
      final n = write(fd, ptr + offset, data.length - offset);
      if (n < 0) throw FileSystemException('write() failed', fd.toString());
      if (n == 0) throw FileSystemException('write() returned 0', fd.toString());
      offset += n;
    }
  } finally {
    calloc.free(ptr);
  }
}

final DynamicLibrary _libc = DynamicLibrary.open('libc.so');
final int Function(int, Pointer<Uint8>, int) _libcWrite = _libc
    .lookupFunction<IntPtr Function(Int32, Pointer<Uint8>, IntPtr), int Function(int, Pointer<Uint8>, int)>('write');
