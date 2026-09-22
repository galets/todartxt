import 'saf_todo_storage.dart';

/// Result of SAF startup load (doc/STORAGE-access-framework.md §2).
class StartupContent {
  final String text;
  final bool offline;
  const StartupContent(this.text, {required this.offline});
}

/// Startup read with transient-provider retry + mirror fallback.
///
/// 1. Try remote `readAll()`; on success refresh mirror, return online.
/// 2. On failure retry once after [delayForRetry] — covers providers like
///    ownCloud whose `DocumentsProvider` throws `KoinApplication has not
///    been started` on cold start before their app init finishes.
/// 3. On final failure return cached mirror as offline; rethrow when no
///    mirror exists so callers can show the permission-lost picker.
Future<StartupContent> loadStartupContent(
  SafTodoStorage storage,
  MirrorCache mirror, {
  Duration delayForRetry = const Duration(milliseconds: 1500),
}) async {
  try {
    final text = await storage.readAll();
    DateTime? mtime;
    try {
      mtime = await storage.lastModified();
    } catch (_) {
      mtime = null;
    }
    await mirror.refreshMirror(
      uri: storage.uri,
      text: text,
      remoteMtime: mtime,
    );
    return StartupContent(text, offline: false);
  } catch (_) {
    // Single retry for transient provider cold-start failures.
    try {
      if (delayForRetry > Duration.zero) {
        await Future.delayed(delayForRetry);
      }
      final text = await storage.readAll();
      DateTime? mtime;
      try {
        mtime = await storage.lastModified();
      } catch (_) {
        mtime = null;
      }
      await mirror.refreshMirror(
        uri: storage.uri,
        text: text,
        remoteMtime: mtime,
      );
      return StartupContent(text, offline: false);
    } catch (_) {
      // Fall through to mirror.
    }
    final cached = await mirror.loadMirror();
    if (cached != null) return StartupContent(cached, offline: true);
    rethrow;
  }
}
