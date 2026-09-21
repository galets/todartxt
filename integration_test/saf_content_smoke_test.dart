import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:saf/saf.dart';
import 'package:todart_txt/features/tasks/saf_test_config.dart';

/// Headless SAF smoke test: invokes NO picker UI.
///
/// Exercises create → write → read → stat roundtrip against ownCloud
/// (`org.owncloud.documents`; Drive unusable on emulator-5554, no sign-in).
/// Tree resolution without UI: first persisted ownCloud grant, else the
/// hardcoded [kTestTreeUri] fallback. Runs unattended on emulator-5554:
/// * grant present → asserts roundtrip, prints SMOKE-PASS.
/// * grant missing / provider offline → prints SMOKE-SKIP and passes, so
///   runs without an ownCloud account stay green.
///
/// One-time setup: app → "Storage location" → "Grant SAF test folder
/// (DEBUG)" → pick the ownCloud folder. Afterwards this test needs no UI.
///
/// Run: `flutter test integration_test/saf_content_smoke_test.dart -d emulator-5554`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SAF content:// roundtrip without UI', (_) async {
    final saf = Saf();
    final payload = smokeTestContent(DateTime.now());

    // Prefer a persisted ownCloud grant (no UI); else hardcoded fallback.
    var treeUri = kTestTreeUri;
    try {
      final persisted = await saf.persistedPermissions();
      for (final p in persisted) {
        if (p.uri.startsWith(kTestProviderPrefix)) {
          treeUri = p.uri;
          break;
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('SMOKE-NOTE: persistedPermissions query failed: $e');
    }
    // ignore: avoid_print
    print('SMOKE-TREE: $treeUri');

    SafDocumentFile? file;
    try {
      file = await saf.writeFileBytes(
        treeUri,
        kTestFileName,
        'text/plain',
        Uint8List.fromList(utf8.encode(payload)),
        overwrite: true,
      );
    } catch (e) {
      // No grant / provider unreachable. NOTE: the hardcoded kTestTreeUri
      // fallback is account-specific and may not exist; the supported path
      // is a persisted ownCloud grant via the DEBUG button, which is picked
      // up above through persistedPermissions().
      // ignore: avoid_print
      print('SMOKE-SKIP: write failed (no grant or offline): $e');
      // ignore: avoid_print
      print('SMOKE-HINT: app → Storage location → Grant SAF test folder '
          '(DEBUG) → pick ownCloud folder, then re-run.');
      return;
    }

    try {
      final readBack = utf8.decode(await saf.readFileBytes(file.uri));
      expect(readBack, payload);

      final meta = await saf.stat(file.uri);
      expect(meta, isNotNull);
      expect(await saf.exists(file.uri), isTrue);

      // ignore: avoid_print
      print('SMOKE-PASS: roundtrip ok uri=${file.uri} bytes=${payload.length}');
    } finally {
      try {
        await saf.delete(file.uri);
        // ignore: avoid_print
        print('SMOKE-CLEANUP: deleted ${file.uri}');
      } catch (e) {
        // ignore: avoid_print
        print('SMOKE-CLEANUP-SKIP: $e');
      }
    }
  });
}
