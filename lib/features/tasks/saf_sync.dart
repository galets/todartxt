import 'package:flutter/services.dart';

/// Requests an expedited manual sync for SAF-backed todo.txt files.
///
/// Any `content://` URI triggers a sync of the user's chosen sync account.
/// The native side persists the account picked via the system account
/// picker, so the grant survives restarts: first use shows the picker,
/// later restarts sync silently. Plain local paths clear the saved account
/// and are no-ops. Failures are swallowed so load/save never breaks
/// because sync failed.
bool isSafSyncUri(String uri) => uri.startsWith('content://');

class SafSync {
  static const MethodChannel channel =
      MethodChannel('todart_txt/saf_sync');

  final Future<void> Function()? _requestSync;

  SafSync({Future<void> Function()? requestSync}) : _requestSync = requestSync;

  /// Fire-and-forget sync request for SAF URIs; clears saved account for
  /// local paths.
  Future<void> maybeSync(String uri) async {
    try {
      if (_requestSync != null) {
        if (!isSafSyncUri(uri)) return;
        await _requestSync();
        return;
      }
      if (!isSafSyncUri(uri)) {
        await channel.invokeMethod('clearAccount');
        return;
      }
      final result = await channel.invokeMethod('requestSync');
      final synced = result is Map ? (result['synced'] as bool?) ?? false : false;
      if (!synced) {
        await channel.invokeMethod('pickAccount');
      }
    } catch (_) {
      // Best-effort only: never break load/save.
    }
  }
}
