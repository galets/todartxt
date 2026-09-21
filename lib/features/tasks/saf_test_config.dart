/// Hardcoded SAF location used by the headless smoke test.
///
/// TEMPORARY (owner-approved): a fixed `content://` tree URI so the
/// integration test can exercise create/read/write with no picker UI.
/// Points at the ownCloud DocumentsProvider (`com.owncloud.android`,
/// authority `org.owncloud.documents`, verified installed on emulator-5554);
/// Google Drive is not usable there (no sign-in). See
/// `doc/STORAGE-access-framework.md` §5.
///
/// Resolution order in the smoke test (all without picker UI):
/// 1. a persisted URI grant whose URI starts with [kTestProviderPrefix]
///    (granted once via the DEBUG button, survives restarts);
/// 2. fallback: the hardcoded [kTestTreeUri] below.
/// Without any grant the smoke test SKIPs instead of failing.
const kTestProviderPrefix = 'content://org.owncloud.documents/tree/';

/// Fallback hardcoded ownCloud tree URI (exact tree/document IDs depend on
/// the signed-in account; prefer the persisted-grant path above).
const kTestTreeUri = '${kTestProviderPrefix}root';

/// File name the smoke test creates/overwrites inside the test tree.
const kTestFileName = 'todart-smoke.txt';

/// Marker content roundtripped by the smoke test.
String smokeTestContent(DateTime now) =>
    'todart SAF smoke ${now.toIso8601String()}\n';
