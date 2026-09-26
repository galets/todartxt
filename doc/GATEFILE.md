# Gatefile Backend Design for todartxt

We no longer speak the gatefile server protocol directly.
All protocol work (REST + SSE, ETag discipline, reconnects) lives in
the [`gatefile_dart`](https://github.com/galets/gatefile_dart) library.
This app only maps config to a `GatefileDocument` and bridges it to
the `TodoStorage` seam.

## 1. Config & URL mapping

`~/.config/todartxt.yaml` (Linux/desktop):

```yaml
todo_file: gatefile://<host>:<port>/<path>   # plain HTTP
todo_file: gatefiles://<host>:<port>/<path>  # HTTPS
api_key: <shared secret>
log_level: warning  # debug | info | warning (default) | error; all go to stderr
```

On Android the `api_key` comes from SharedPreferences (GUI config
dialog) instead of the YAML file.

Mapping (`storage_location.dart`):

| Scheme      | Endpoint URI           | Example                                                                                   |
| ----------- | ---------------------- | ----------------------------------------------------------------------------------------- |
| `gatefile`  | `http://` + remainder  | `gatefile://127.0.0.1:8654/gatefile/todo.txt` → `http://127.0.0.1:8654/gatefile/todo.txt` |
| `gatefiles` | `https://` + remainder | `gatefiles://example.com/gatefile/todo.txt` → `https://example.com/gatefile/todo.txt`     |

Missing/wrong key → library throws `AuthFailed`. Fatal config error:
surface to user, do not retry with same key.

## 2. Library interface (`gatefile_dart`)

Full replace only. Version is server `ETag`. `put` sends held ETag
as `If-Match`.

```dart
final doc = GatefileDocument(baseUrl: base, apiKey: key);

// read-modify-write
try {
  final cur = await doc.get();
  await doc.put('$cur hello');
} on Conflict {
  final fresh = await doc.get();
  await doc.put('$fresh hello');
}

// subscribe
doc.updated.listen((_) async {
  final cur = await doc.get();
  render(cur);
});
```

Behavior (owned by the library, not this app):

- `get()` returns body, stores ETag.
- `put()` replaces doc. Stale ETag throws `Conflict`: re-`get`,
  merge, retry.
- `updated` fires per server change (own echo skipped). No payload:
  call `get()` to refresh.
- `close()` stops SSE polling.

## 3. App wiring

- `GatefileTodoStorage` (`todo_storage.dart`): thin `TodoStorage`
  bridge. `readAll` is `get`, `writeAll` is `put`, `updated`
  delegates to the document. `Conflict`/`AuthFailed` propagate to
  callers.
- `main.dart`: backend switch (`gatefile://` → `GatefileTodoStorage`
  with platform key source), subscribes to `updated` → `reload()` +
  UI refresh, closes document on dispose.
- `task_list_page.dart`: skips focus-resume reload for gatefile
  backends (SSE covers it); config dialog builds
  `GatefileTodoStorage(gatefileEndpointUri(path), apiKey)`.
