import 'dart:convert';
import 'dart:io';

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
/// Write: truncate + rewrite the picked document through a `wt` file
///   descriptor (`/proc/self/fd/<fd>`), so any provider works.
/// Stat: `stat(uri).modified`.
SafTodoStorage safStorageForUri(String uri, [Saf? saf]) {
  final s = saf ?? Saf();
  return SafTodoStorage(
    uri,
    readBytes: (u) async => utf8.decode(await s.readFileBytes(u)),
    writeBytes: (u, text) async {
      await s.withFileDescriptor(u, 'wt', (fd) async {
        await File(fd.path).writeAsString(text, encoding: utf8);
      });
    },
    statMtime: (u) async {
      final info = await s.stat(u);
      if (info == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(info.lastModified);
    },
  );
}
