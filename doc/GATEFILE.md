# Gatefile Backend Design for todartxt

## 1. Config & URL mapping

`~/.config/todartxt.yaml`:

```yaml
todo_file: gatefile://<host>:<port>/<path>   # plain HTTP
todo_file: gatefiles://<host>:<port>/<path>  # HTTPS
api_key: <shared secret>
log_level: warning  # debug | info | warning (default) | error; all go to stderr
```

Mapping:

| Scheme      | Endpoint URI           | Example                                                                                   |
| ----------- | ---------------------- | ----------------------------------------------------------------------------------------- |
| `gatefile`  | `http://` + remainder  | `gatefile://127.0.0.1:8654/gatefile/todo.txt` → `http://127.0.0.1:8654/gatefile/todo.txt` |
| `gatefiles` | `https://` + remainder | `gatefiles://example.com/gatefile/todo.txt` → `https://example.com/gatefile/todo.txt`     |

All requests send `Authorization: Bearer <api_key>`. Missing/wrong key → `401`. Treat as fatal config error: surface to user, do not retry with same key.

Base URI is used both for document ops (`GET`/`POST`) and subscribe (`GET <uri>?subscribe`).

## 2. Standard operations (from gatefile HOWTO)

### 2.1 READ -- `GET <uri>`

- Response: body `text/plain` (todo.txt content) + `ETag` header (current version, md5 of content).
- Client MUST persist the ETag alongside content in memory (`currentEtag`).
- Extract ETag case-insensitively, strip whitespace/CR.
- No `If-Match` needed.

```
GET /gatefile/todo.txt
Authorization: Bearer $API_KEY
→ 200, ETag: <etag>, body: <todo.txt>
```

### 2.2 WRITE -- `POST <uri>` (full replace, optimistic concurrency)

- `POST` replaces the whole document.
- REQUIRED: `If-Match: <currentEtag>` + `Content-Type: text/plain` + full new body.
- Success → `200 OK`. The ETag changes server-side; client must refresh (re-`GET`, or use ETag from `409`/SSE event -- safest is re-`GET`).
- Failure modes:

| Status                    | Cause                                                                                | Action                                                                                                |
| ------------------------- | ------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------- |
| `400`                     | Missing `If-Match`                                                                   | Client bug -- never send POST without ETag. Re-GET to obtain ETag, then retry.                        |
| `401`                     | Bad/missing `Authorization`                                                          | Fatal. Stop retrying, prompt for api_key.                                                             |
| `409`                     | Stale/wrong ETag (race: another process updated first). Response notes current ETag. | Race-condition path (§4). Re-GET, re-apply local change onto fresh content, retry POST with new ETag. |
| `423`                     | Update in progress (server hook running, one-at-a-time)                              | No state change. Retry with backoff, SAME ETag (still current unless SSE/GET says otherwise).         |
| `500`                     | Hook exited non-zero. Doc IS persisted, but NO SSE broadcast sent.                   | Re-GET to get authoritative content + ETag, reconcile.                                                |
| network/timeout/5xx other | Server may have failed                                                               | Retry (§5).                                                                                           |

### 2.3 SUBSCRIBE -- `GET <uri>?subscribe` (SSE)

- Open long-lived `GET <uri>?subscribe` with `Authorization` header, `Accept: text/event-stream`, no buffering.
- Server immediately sends current ETag, then one `<etag>\n\n` message per subsequent successful `POST`.
- `Content-Type: text/event-stream`. Message format is plain `<etag>\n\n` (no `data:` framing).
- Closing connection = unsubscribe (server-side automatic).
- Delivery is unbuffered: events emitted while nobody is subscribed are LOST. Therefore SSE is only a hint -- always re-`GET` to converge.
- `?subscribe` without auth → `401` (fatal, same as above).

## 3. ETag discipline (core invariant)

- Client holds exactly one `currentEtag`, obtained from the last `GET` response (or `409` response's `Current:` hint, verified by re-`GET`).
- Rules:
  1. Every `POST` uses `If-Match: currentEtag`.
  2. On EVERY `GET 200`, replace `currentEtag` with response ETag -- even if body is identical.
  3. On EVERY SSE event carrying `<etag>`: if `eventEtag != currentEtag`, the file changed remotely → re-`GET` immediately (which refreshes `currentEtag`). If equal, ignore (own echo or duplicate).
  4. On `409`, the held ETag is stale. MUST refresh via re-`GET` before next `POST` (do not trust-merge on the `409`-quoted ETag alone; fetch body too).
  5. Never cache ETag across app restarts without re-`GET` -- startup always begins with `GET`.
  6. Never send `POST` with empty/absent ETag.

## 4. Workflows

### 4.1 Startup / load

1. Parse `todo_file` scheme → endpoint URI + TLS mode; read `api_key`.
2. `GET` → store `(content, currentEtag)`, render task list.
3. Open SSE connection (§6).
4. On `GET` failure: retry with backoff (§5); show offline/cached state if a previous local copy exists.

### 4.2 Local edit → save

Single-writer discipline in client: serialize local saves through one async queue/mutex so only one in-flight `POST` exists at a time.

1. Build new full document text from current in-memory model (which was derived from last `GET` + local edits).
2. `POST` body with `If-Match: currentEtag`.
3. On `200`: re-`GET` (refresh `currentEtag` + confirm content; also covers the `500`-with-persist ambiguity and hook delay).
4. On `409` (race -- another process committed first): re-`GET` latest, rebase/re-apply the user's intent onto fresh text (per todo.txt merge policy: line-based; on conflict prefer remote + re-applied local op, or surface conflict to user), then `POST` again with the NEW ETag. Bound retries (e.g. 3–5 rebases), then surface conflict to user rather than looping forever.
5. On `423`: keep SAME `currentEtag`, wait with backoff/jitter, retry `POST`. Before each retry, check whether `currentEtag` was invalidated by a concurrent SSE-triggered `GET`; if so, follow the `409` rebase path instead.
6. On `500`: re-`GET`; if content equals what we tried to write → treat as success (update `currentEtag`); else rebase + retry.
7. On network/5xx/timeout: retry same `POST` with SAME ETag (§5) -- unless an intervening SSE/`GET` proved the ETag stale, in which case rebase first.

Race note: two local rapid edits must not both use the same ETag. Queue them: edit2's `POST` waits for edit1's post-`GET` (new ETag) before sending.

### 4.3 Remote update notification

1. SSE event `<etag>` arrives.
2. If `<etag> == currentEtag`: ignore.
3. Else: `GET` → replace `(content, currentEtag)`, re-render, discard/merge any uncommitted local draft per policy (committed local POST in flight takes the §4.2 race path; pure UI draft should be rebased, not silently dropped -- prompt if truly conflicting).
4. Debounce: multiple events in quick succession → single trailing `GET`.

### 4.4 SSE failure / reconnect

- Detect failure: HTTP error, `401`, socket close, timeout, malformed stream, or idle watchdog (no bytes for N seconds -- server only speaks on change, so use TCP keepalive + optional idle re-`GET` poll as safety net).
- On ANY failure except `401`: immediately attempt reconnect, then fall back to retry loop with exponential backoff + jitter (e.g. 1s → 2s → 5s → 15s → 30s cap), retrying indefinitely while the backend is selected. Log each attempt.
- On reconnect: the server replays the CURRENT ETag as the first event → normal compare-and-`GET` logic converges any missed updates automatically. Optionally force one `GET` right after (re)connect to cover events lost while unsubscribed (delivery is unbuffered).
- `401` on subscribe: fatal config error -- do not loop; surface to user.
- Only one SSE connection at a time; guard with a manager that kills the old socket before opening a new one. Reconnect must be triggered from a single place (connection-state machine) to avoid reconnect storms.
- App lifecycle: pause SSE in background, re-establish on resume + immediate `GET`.

## 5. Server-failure & retry policy

- Retryable: network errors, timeouts, `423`, `500`, `502/503/504`, unknown 5xx.
  - Strategy: exponential backoff with jitter + cap; `423` (lock is short-lived, hook execution) uses shorter base delay (e.g. 300–500ms start).
  - `POST` retries reuse the SAME ETag unless a fresh `GET`/SSE event proved it stale.
  - Bound `POST` retry count for user-initiated saves (e.g. ~5 attempts), then surface error with "Retry" action; SSE reconnect retries are UNBOUNDED.
- Non-retryable (do not loop): `401` (bad key), `400` on POST (client bug -- fix ETag handling, single re-`GET` then one retry max), `409` (not a blind retry -- must rebase first, bounded).
- Idempotence caution: `POST` is full-replace, not idempotent under races. Never auto-retry a timed-out `POST` blindly if an SSE event arrived in the meantime -- re-`GET` first, then decide (success-check vs rebase).

## 6. Architecture sketch (flutter/dart)

- `GatefileBackend implements TodoBackend`:
  - `Future<(String body, String etag)> fetch()` -- `GET`, updates `currentEtag`.
  - `Future<void> save(String newBody)` -- serialized `POST` with `If-Match`, handles 409/423/500 per §4.2.
  - `Stream<String> watchEtags()` -- SSE client (`http.Client` streaming request to `?subscribe`, split on `\n\n`, trim, emit non-empty token).
  - `String? currentEtag` held privately in the backend; UI layer never touches it.
- Wiring: startup `fetch` → render; `watchEtags().listen(onEvent → maybe fetch)`; local edits funneled through a save queue (`Future` chain / mutex). Cancel SSE subscription on backend dispose.
- Config: `todo_file` scheme switch (`gatefile`/`gatefiles`) selects this backend; `api_key` injected as Bearer header on every request.

## 7. Scenario checklist (all covered)

- [x] Initial read + ETag capture (§2.1, §4.1)
- [x] Write with correct ETag (§2.2, §4.2)
- [x] ETag held + refreshed on every GET/non-matching ETag (§3)
- [x] Race: remote update between GET and POST → 409 → re-GET, merge, retry (§4.2)
- [x] Queued local edits sharing one ETag (§4.2 race note)
- [x] SSE subscribe, first-event current ETag, per-POST broadcasts, re-GET on mismatch (§2.3, §4.3)
- [x] SSE failure → immediate reconnect + bounded-backoff infinite retry (§4.4)
- [x] Single SSE connection, no reconnect storms, resume/pause lifecycle (§4.4)
- [x] Events lost while unsubscribed → reconnect/first-event + safety GET (§4.3, §4.4)
- [x] 423 hook-lock → same-ETag backoff retry (§2.2, §4.2, §5)
- [x] 500 hook-failure (persisted, no broadcast) → re-GET reconcile (§2.2, §4.2)
- [x] 400 missing ETag (never happens by construction) (§2.2, §5)
- [x] 401 bad key → fatal, no retry loop (§2, §4.4, §5)
- [x] Network/5xx/timeout → backoff retry; ambiguous POST resolved by re-GET (§5)
