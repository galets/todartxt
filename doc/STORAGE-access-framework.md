# SAF storage integration (Android)

Goal: let the Android app open `todo.txt` from any DocumentProvider
(Google Drive, Nextcloud/OwnCloud, local storage) via the Storage Access
Framework, so one file can be shared between multiple machines. Linux builds
must keep working unchanged (plain `dart:io` file path, e.g. `~/Tasks/todo.txt`).

Reference: https://developer.android.com/guide/topics/providers/document-provider

Verified on emulator-5554 (2026-09-21): `com.google.android.apps.docs`
(Drive) + `com.android.externalstorage` + `com.android.providers.downloads`
are installed, so Drive-backed SAF testing is possible.

## 1. Current state (why SAF is needed)

- `TaskRepository` uses `dart:io File(path)` + `TodoTxt.load/save` stream.
  Works on Linux and app-private Android dirs, breaks on scoped storage
  (`/storage/emulated/0/...` needs `MANAGE_EXTERNAL_STORAGE`, Play-review
  sensitive) and cannot address Drive/Nextcloud at all (no filesystem path,
  only `content://` URIs).
- `file_picker.getDirectoryPath()` returns a filesystem path, not a
  persistable SAF grant. `file_picker` #1825 notes `takePersistableUriPermission`
  is missing. So it cannot give durable Drive access.
- `storage_location.dart` persists a raw `dir` string in SharedPreferences.
  For SAF this must become a persisted **tree/document URI string** +
  `takePersistableUriPermission()` grant instead.

Decision: add Flutter plugin `saf` (^1.0.5, `ivehement.com`, MIT,
`Saf()` single class, minSdk 21) for pickers + persisted permissions +
streamed read/write. Keep `dart:io` path behind a `StorageBackend`
interface so Linux never touches SAF.

Proposed abstraction:

```dart
abstract class TodoStorage {
  Future<String> readAll();          // full todo.txt text (offline cache aware)
  Future<void> writeAll(String text);// atomic replace via SAF output stream
  Future<DateTime?> lastModified();
  Future<bool> isReachable();        // false when offline / provider gone
}
class FileTodoStorage implements TodoStorage // Linux + legacy local path
class SafTodoStorage implements TodoStorage  // content:// URI via saf plugin
```

`TaskRepository` keeps its in-memory model/undo, but loads/saves through
`TodoStorage` (parse `readAll()` lines with `TodoTxt.load`, serialize to
string for `writeAll()`).

## 2. Offline usage

- SAF `content://` reads hit the provider; Drive serves cached bytes when
  offline **only if** the file is marked "Available offline" in Drive.
  Otherwise read throws (`SafIoException` / `FileNotFoundException`).
- Required behavior:
  1. Maintain a local mirror: `<app docs>/saf-mirror/todo.txt` + `meta.json`
     (`uri`, `lastSync`, `lastKnownRemoteMtime`).
  2. Startup: try remote `readAll()`; on failure fall back to mirror and show
     "Offline — showing cached copy (timestamp)".
  3. Every successful remote read/write refreshes the mirror.
  4. Writes while offline update the mirror + set `dirty` flag; on
     reconnect, prompt (see §4 dialog 4) before pushing.
- No background sync daemon in v1; sync on launch, on resume
  (`didChangeAppLifecycleState`), on explicit Save/Refresh.

## 3. Concurrency and updates

Constraints: todo.txt is a dumb text file, no locking/ETag across providers.
Drive `lastModified` via `DocumentFile.COLUMN_LAST_MODIFIED` is best-effort
and may be stale offline.

- Policy v1: **last-write-wins with explicit conflict prompt** (no silent merge,
  no auto-merge of lines — too surprising for a task list).
- Mechanism:
  1. Store `baseMtime` + `baseHash` at load time.
  2. Before each `save()`: re-query `lastModified()` + remote hash.
  3. If unchanged → write through.
  4. If changed remotely (another machine saved) → do NOT overwrite;
     show conflict dialog (§4 dialog 5): Keep mine / Load theirs / Save a copy
     (`todo-conflict-<ts>.txt` next to the file via SAF create).
  5. Every mutation saves immediately (no dirty state); a background
      save must also do the
      check-then-write; if conflict while backgrounded, keep local state and
      prompt on next resume rather than overwriting. The conflict dialog
      pre-selects **Keep mine** (owner decision).
- Within one device the existing `_history`/undo + immediate `save()` per
  mutation stays; only the transport changes.
- Optional v2: per-line 3-way merge; explicitly out of scope for v1.

## 4. Dialogs (no CLI on Android)

CLI arg (`args[0]`) stays Linux-only. On Android all location choice is UI:

1. **First-run / empty location** — bottom sheet on launch when no persisted
   URI: "Where is your todo.txt?" → [Open file…] (`ACTION_OPEN_DOCUMENT`,
   `text/plain`) / [Use folder…] (`ACTION_OPEN_DOCUMENT_TREE`) / [Use local
   file instead]. Replaces current "No todo.txt supplied" error screen.
2. **System SAF picker** (via `saf` plugin: `openDocument()` /
   `pickDirectory()`). User navigates to Drive/Nextcloud/local. App calls
   `takePersistableUriPermission(R+W)`, persists URI string in
   SharedPreferences (`todo_txt_saf_uri`), caches content, closes picker.
3. **Storage location info** — extend existing `AlertDialog` ("Storage
   location"): show provider label + URI + last-sync + offline status, buttons
   [Refresh] [Change…] [Make available offline (how-to)] [Close].
4. **Offline banner/dialog** — non-blocking banner "Offline — cached copy";
   on reconnect with dirty mirror: "Push N offline change(s) to Drive?" →
   [Push] [Discard] [Keep editing].
5. **Conflict dialog** — "todo.txt changed on another device (time X). Your
   version has N unsaved change(s)." → [Keep mine (overwrite)] (default,
   pre-selected) [Load theirs (discard mine)] [Save my copy separately].
   Never auto-overwrite.
6. **Permission-lost dialog** — when persisted grant revoked/file deleted:
   "Access expired — pick the file again" → re-opens dialog 1. Handle
   `SecurityException` / null query gracefully.
7. **"Make available offline" hint** — Drive offline caching is a Drive-app
   setting per file; we can only link/explain, not force it.

Permissions to drop: `MANAGE_EXTERNAL_STORAGE` / `WRITE_EXTERNAL_STORAGE`
requests at startup (`ensureSharedStorageAccess`) become unnecessary once SAF
is the path; keep only for legacy local-path migration, then remove to ease
Play review. No new manifest permission needed for SAF beyond the intents.

## 5. Feature testing (emulator-5554 + unit)

Emulator has Drive (`com.google.android.apps.docs`); sign-in state unknown,
so tests must degrade gracefully.

- **Unit/widget (CI, no device):**
  - `FakeTodoStorage` in-memory impl; conflict matrix (unchanged/changed/
    offline), dirty-flag, mirror fallback.
  - URI persistence: save/restore URI string, revoked-grant path.
  - Existing `defaultTodoPathAsync` / `effectiveTodoPath` tests unchanged.
- **Manual integration on emulator-5554:**
  1. `adb install -r build/app/outputs/flutter-apk/app-release.apk`
  2. Launch → pick `todo.txt` from Drive via SAF → edit → Save → verify on
     second machine / Drive web.
  3. Airplane-mode test: load cached copy, edit offline, reconnect, push prompt.
  4. Conflict test: modify same file from Drive web, then save from app →
     conflict dialog appears.
  5. Revoke test: remove persisted grant (App info → clear access) or delete
     file → permission-lost dialog.
  6. Log checks: `adb logcat`, `adb shell content query --uri <uri>`.
- **Automated integration (optional):** `integration_test` + `patrol`/ADB
  script driving `ACTION_OPEN_DOCUMENT` is flaky (system picker UI); keep
  automated coverage at the `TodoStorage` seam with fakes, manual for real
  Drive. OwnCloud/Nextcloud provider can be substituted the same way if
  installed later — no code change (any `DocumentsProvider` works).

## 6. Linux builds unaffected

- All SAF code isolated: `lib/features/tasks/saf_todo_storage.dart` (Android-only
  import of `package:saf`) + `todo_storage.dart` interface. Linux path
  (`FileTodoStorage`) has zero new dependencies.
- `pubspec.yaml`: `saf` plugin is Android-only stub on other platforms; verify
  `flutter build linux`, `flutter test`, `flutter analyze` pass.
- `effectiveTodoPath(args)` keeps priority: CLI arg > persisted SAF URI
  (Android) > legacy custom dir > platform default. Linux never reads the SAF
  key.
- No manifest/permission changes affect Linux; no `dart:io` behavior change.

Scope: single `todo.txt` only (no `done.txt` handling in v1).

## 7. Migration plan (v1 slices)
1. Introduce `TodoStorage` interface + `FileTodoStorage` wrapper (no UX change).
2. Add `saf` dependency + `SafTodoStorage` (read/write/stat via URI) + mirror
   cache.
3. Replace first-run error with location picker (dialogs 1–3); persist URI.
4. Add offline banner + reconnect push (dialog 4) + conflict dialog (5) +
   permission-lost (6).
5. Remove `MANAGE_EXTERNAL_STORAGE` request path once SAF is default; keep
   "import legacy local file" migration (`migrateTodoFile` equivalent over
   storages).

Decisions (confirmed by owner):
- Default on conflict: pre-select "Keep mine".
- Scope: single `todo.txt` only.
