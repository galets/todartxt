import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:saf/saf.dart';
import 'package:todart_txt/features/tasks/saf_bindings.dart';

/// Regression test for "KoinApplication has not been started".
///
/// ownCloud's `DocumentsStorageProvider` throws
/// `IllegalStateException: KoinApplication has not been started` when
/// queried cold (right after force-stop, before its DI graph is up).
///
/// Re-runnable, read-only (no writes/deletes):
/// 1. Grant once: app → Choose file → ownCloud → Personal → file.txt
///    (persisted grant survives `adb install -r` / streamed installs;
///    a full uninstall wipes it and this test SKIP/FAILs on grant loss).
/// 2. (on host) `adb shell am force-stop com.owncloud.android`
/// 3. `flutter test integration_test/owncloud_koin_regression_test.dart -d emulator-5554`
/// 4. Observe `KOIN-FAIL` (raw single read threw = bug visible) and
///    `KOIN-SUCCEED` (retrying read via [safStorageForUri] recovered).
///
/// The test FAILS when the retrying read cannot recover (pre-fix
/// behaviour: single attempt, load error at startup).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ownCloud cold-start read of /Personal/file.txt', (_) async {
    const docUri = 'content://org.owncloud.documents/document/10';
    final saf = Saf();

    // Phase 1: raw single attempt — documents the provider bug.
    try {
      final bytes = await saf.readFileBytes(docUri);
      // ignore: avoid_print
      print('KOIN-NOTE: raw read ok (${bytes.length} bytes, provider warm)');
    } catch (e) {
      // ignore: avoid_print
      print('KOIN-FAIL: raw read threw (bug visible): $e');
    }

    // Phase 2: production path with retry — must recover.
    try {
      final text = await safStorageForUri(docUri).readAll();
      // ignore: avoid_print
      print('KOIN-SUCCEED: retry read ${text.length} chars head='
          '${utf8.encode(text).take(80).toList()}');
    } catch (e, st) {
      // ignore: avoid_print
      print('KOIN-FAIL: retry read threw: $e\n$st');
      fail('KOIN-FAIL: cold read did not recover: $e');
    }
  });
}
