# Cloud Sync (Supabase, step 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Signed-in devices sync themes, fonts, playlists (incl. Favorites), track details, listens, lyrics and YtSeen through the user's Supabase account, live; local songs a device never had are hidden in its playlists; home-network sync is removed.

**Architecture:** Supabase holds one owner-scoped `sync_rows` table and a private `sync-files` bucket. A `CloudSync` engine in the app pushes rows changed since a local watermark (`ChangeFeed.since`) through a `push_rows` function that keeps the newer clock, pulls rows changed since a server watermark (`pull_rows`) and applies them with the existing `RowApplier`, and is woken by Supabase Realtime and by local writes (debounced). Files referenced by synced rows go through Storage. The LAN sync code is deleted at the end, keeping `SyncColumns`, `SyncStamp`/HLC, `ChangeFeed`, `RowApplier`, `SyncRow`.

**Tech Stack:** Flutter, drift, `supabase_flutter` 2.18.3 (Postgrest, Realtime, Storage), Riverpod.

**Spec:** `docs/superpowers/specs/2026-11-05-cloud-sync-design.md`

Flutter is at `~/development/flutter/bin` (not on PATH): run commands with
`export PATH=$HOME/development/flutter/bin:$PATH` first. Memory on this machine is limited: run focused tests while iterating and the full suite once per task; the stats "… under 500 ms" timing tests fail under load (on main too).

## Global Constraints

- Synced tables exactly: `SyncTable.values` (tracks, playlists, playlist_entries, yt_seen, themes, fonts, lyrics, listens). Never synced: `LocalFiles`, `PlaylistDevicePrefs`, `LibraryFolders`, `Settings`, `PlayHistory`, downloads, local audio files.
- Merge rule: per row, the newer HLC `clock` wins, everywhere (server and device); tombstones are ordinary rows (the user decided "the newer action wins"). The clash dialog is not used.
- Only signed-in users sync; signed out = no network sync activity at all.
- A user can read/write only their own `sync_rows` and `sync-files/<uid>/…`. No service-role key in the app.
- Push: debounced ~3 s after a local write; pull: on app start (after sign-in restores), on reconnect, on Realtime notification, and after a push. No polling loops.
- Watermarks per account: last pushed local seq and last pulled server seq, stored in `Settings` under keys including the account id (`cloud_push_seq:<uid>`, `cloud_pull_seq:<uid>`); `cloud_last_account` holds the last signed-in account id.
- Hidden entries: a playlist entry whose track is a local-library track (`source` not YouTube) with **no** `LocalFiles` row on this device is excluded from lists, counts, total length, play queues and Favorites. Tracks with a `LocalFiles` row in any state (incl. `missing`) show as today.
- Copy (exact): status "Synced", "Syncing…", "Waiting for internet", "Last synced <relative time>"; log-out warning "Some changes on this device haven't been uploaded yet. Log out anyway?" with "Log out" / "Cancel"; account switch "This device has a library from another account. Merge it into this account, or start empty?" with "Merge" / "Start empty".
- "Start empty" removes this device's playlists + entries (Favorites emptied, the Favorites playlist itself kept), themes, fonts (rows and files), lyrics, listens, yt_seen locally; keeps `Tracks`, `LocalFiles`, downloads, settings.
- Deleting the account deletes the user's `sync_rows` (FK cascade) and `sync-files/<uid>/` (app deletes before the RPC); devices keep their local library.
- Removing LAN sync: drift schema 8 → 9 drops `Peers`; Settings → Sync devices and all pairing/discovery/server/client/SPAKE2/file-transfer/runner/responder/merger/clash code and their tests go.

## Review Focus

1. Two devices edit the same playlist offline, then both come online → both converge to the same rows (newer clock per row), no duplicate playlists (RowApplier's natural-key claim) — test in Task 2 with two in-memory databases and a fake remote.
2. A push and a pull racing (Realtime fires mid-push) → no row is lost or applied twice; watermarks only move after success — test in Task 2.
3. First sign-in on a device with a big library (10k tracks, 50k listens) → paged push and pull (≤ 500 rows per call), memory bounded, progress visible as "Syncing…" — test in Task 2 (row counts) and docs note.
4. Signed out → no Supabase calls from sync at all; log out while offline with unsent rows → the warning — test in Task 2 and Task 4.
5. A user can't read another user's rows through `pull_rows` or Realtime — checked in Task 1 on local Supabase.

---

### Task 1: Supabase schema for sync

**Files:**
- Create: `supabase/migrations/20261106120000_cloud_sync.sql`
- Modify: `docs/supabase.md` (apply this migration; Realtime is enabled by the migration; free-tier limits 500 MB DB / 1 GB storage; a rough size per 10k tracks + 50k listens)
- Modify: `docs/manual-test-checklist.md` ("Cloud sync" section)

**Interfaces (produces):**
- `public.sync_rows(user_id uuid not null references auth.users on delete cascade default auth.uid(), tbl text not null, id text not null, clock text not null, origin_device text not null, deleted boolean not null, data jsonb not null, server_seq bigint not null, updated_at timestamptz default now(), primary key (user_id, tbl, id))`, index on `(user_id, server_seq)`. `server_seq` from a sequence, assigned on every insert/update.
- RLS on: select only `user_id = auth.uid()`; no direct insert/update/delete for clients (all writes through `push_rows`).
- `public.push_rows(rows jsonb) returns integer` — security definer, `search_path = ''`, granted to `authenticated` only; for each element `{tbl, id, clock, origin_device, deleted, data}` upserts for `auth.uid()` only when the row is new or `excluded.clock > existing.clock` (text comparison works for the packed HLC — confirm against `lib/data/hlc.dart` or wherever `HlcClock` packs; if not lexically ordered, compare via its components); rejects `tbl` not in the eight wire names; returns the number written. Max 500 elements per call.
- `public.pull_rows(after bigint, max integer default 500) returns setof public.sync_rows` (security invoker; RLS filters), ordered by `server_seq`.
- Realtime: add `public.sync_rows` to the `supabase_realtime` publication (RLS applies to Realtime postgres_changes for `authenticated`).
- Storage: private bucket `sync-files`; policies select/insert/update/delete only under `(storage.foldername(name))[1] = auth.uid()::text`; file names `<uid>/<kind>/<hash>.<ext>` (`kind` = `font` | `art`).
- `public.delete_my_account()` unchanged (rows cascade).

- [ ] **Step 1:** Write the migration and docs.
- [ ] **Step 2: Validate** on the local Supabase (`npx --yes supabase@3 db start` + `db reset`): push newer/older clocks; push for another user is impossible (uid from `auth.uid()` only); pull returns only own rows in seq order; a non-wire `tbl` is rejected; Realtime publication includes the table; storage policies; cascade on user delete. Stop and remove containers/volumes afterwards (leave the unrelated `elearning-mysql` container alone).
- [ ] **Step 3: Commit** `feat: Supabase schema for cloud sync`

### Task 2: The cloud sync engine

**Files:**
- Create: `lib/sync/cloud/cloud_remote.dart` (`abstract class CloudRemote` + `SupabaseCloudRemote`), `lib/sync/cloud/cloud_sync.dart` (`CloudSync`), `lib/sync/cloud/sync_status.dart`
- Modify: `lib/main.dart`, `lib/providers.dart` (create `CloudSync` once; start/stop it from `accountStateProvider`), `lib/data/settings_repository.dart` (keys)
- Test: `test/sync/cloud/*.dart`

**Interfaces:**
- Consumes: `ChangeFeed.since(seq, limit:)`, `ChangeFeed.safeHigh()`, `RowApplier.apply(rows)`, `SyncRow`, `SyncTable`, `SyncStamp` (all existing); `AccountService.states` (step 1).
- Produces:
  - `abstract class CloudRemote { Future<int> push(List<SyncRow> rows); Future<List<(int serverSeq, SyncRow row)>> pull(int after, {int max = 500}); Stream<void> changes(String userId); Future<void> close(); }`
  - `enum SyncPhase { idle, syncing, offline, error }` and `class SyncStatus { final SyncPhase phase; final DateTime? lastSynced; }`
  - `class CloudSync { CloudSync({required AppDatabase db, required SyncStamp stamp, required CloudRemote remote, required SettingsRepository settings, Stream<NetworkStatus>? network}); Stream<SyncStatus> get status; Future<void> start(String userId); Future<void> stop(); Future<void> syncNow(); Future<bool> hasUnsent(); void localWrite(); }`
  - A trigger for `localWrite()`: whichever hook the repositories already have when they stamp a row (find it; else a drift `tableUpdates` stream over the synced tables), debounced 3 s.
  - Push loop: page `ChangeFeed.since(pushSeq)` → `remote.push` → advance `cloud_push_seq:<uid>` to the page's last seq only after success; repeat until no `next`. Pull loop: `remote.pull(pullSeq)` → `RowApplier.apply` (one transaction per page) → advance `cloud_pull_seq:<uid>`; repeat while a full page came back. Rows the applier rewrites (natural-key claims) get new local seqs and go up on the next push.
  - Never pushes rows whose `originDevice`/seq came from the pull it just applied unless they changed locally (the applier keeps incoming seq bookkeeping; check `RowApplier` and avoid echo loops).
  - One sync at a time; a trigger during a sync schedules exactly one follow-up.
  - Account switch: `start(uid)` with `cloud_last_account` set to a different id → asks a `Future<bool> Function() askMerge` callback (UI in Task 4) — true = merge (keep data, reset watermarks for the new account), false = start empty (`wipeForNewAccount()` per Global Constraints) — then records `cloud_last_account = uid`.

- [ ] **Step 1: Write the failing tests** (fake `CloudRemote` holding rows per user in memory with the server's newer-clock rule; two `AppDatabase.inMemory` devices)

```dart
test('a playlist made on device A appears on device B after both sync', ...);
test('offline edits on both devices converge, newer clock per row; a newer delete wins', ...);
test('no duplicate playlist when both devices create "Chill" offline', ...);
test('pages of 500: 1200 rows push in 3 calls and pull in 3 calls', ...);
test('a failed push leaves the watermark; the retry sends the same rows', ...);
test('a Realtime change during a push triggers exactly one follow-up pull', ...);
test('applying pulled rows does not push them back (no echo)', ...);
test('signed out: no remote calls', ...);
test('hasUnsent is true after a local write and false after a push', ...);
test('switching to another account asks; Start empty wipes the synced tables but keeps tracks and local files', ...);
test('status goes syncing -> idle with lastSynced; offline -> offline phase', ...);
```

- [ ] **Step 2: Run** `flutter test test/sync/cloud/` → FAIL.
- [ ] **Step 3: Implement.** `SupabaseCloudRemote` uses `rpc('push_rows', params: {'rows': [...]})`, `rpc('pull_rows', params: {'after': n, 'max': 500})`, and a Realtime channel `postgres_changes` on `sync_rows` filtered `user_id=eq.<uid>` that only signals "something changed" (the pull fetches the rows).
- [ ] **Step 4: Run** focused + full suite; analyze.
- [ ] **Step 5: Commit** `feat: cloud sync engine`

### Task 3: Synced files (fonts, non-YouTube artwork)

**Files:**
- Create: `lib/sync/cloud/cloud_files.dart`
- Modify: `lib/sync/cloud/cloud_sync.dart` (after pull/push, reconcile files), `lib/sync/cloud/cloud_remote.dart` (upload/download/list/delete in `sync-files`)
- Test: `test/sync/cloud/cloud_files_test.dart`

**Interfaces:**
- Produces: `class CloudFiles { Future<void> reconcile(String userId); Future<void> deleteAll(String userId); }` — for each live `Fonts` row: upload `<appData>/fonts/<fileHash>.<ext>` if the bucket lacks `<uid>/font/<fileHash>.<ext>`, download it if the local file is missing. For artwork: only `artworkRef`s that are not re-fetchable from YouTube (find how `ArtCache` names YouTube thumbnails vs embedded art; YouTube-sourced art is skipped). Names validated like `FileRef` does today (hash + ext rules) before touching the filesystem.
- `AccountService.deleteAccount` (step 1) calls `CloudFiles.deleteAll(uid)` before the RPC.

- [ ] **Step 1: Write the failing tests** (fake remote storage): font uploaded once, downloaded on the other device; YouTube art never uploaded; embedded art synced; a bad name refused; deleteAll empties the folder.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** focused + full suite; analyze.
- [ ] **Step 5: Commit** `feat: fonts and artwork follow the account`

### Task 4: Hidden local songs, status, log-out and account-switch UI

**Files:**
- Modify: the playlist/Favorites queries and counts in `lib/library/library_repository.dart` and `lib/library/favorites.dart` (and wherever play queues are built from a playlist) to exclude hidden entries per Global Constraints.
- Modify: `lib/ui/account/account_section.dart` (status line from `CloudSync.status`; "Sync now" text button), log-out flow (warning when `hasUnsent()`), account-switch dialog wired to `askMerge`.
- Test: `test/library/hidden_entries_test.dart`, `test/ui/account/sync_ui_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
test('a local track with no LocalFiles row on this device is hidden from the playlist, its count and length', ...);
test('a local track marked missing on this device still shows (with Locate)', ...);
test('YouTube tracks always show; Favorites follows the same rule; play-all skips hidden', ...);
uiTest('Account shows Synced / Syncing… / Waiting for internet and Last synced', ...);
uiTest('log out with unsent changes asks first; Cancel keeps you signed in', ...);
uiTest('logging in as a different account asks Merge / Start empty', ...);
```

- [ ] **Step 2: Run** → FAIL. **Step 3: Implement** with the exact copy. **Step 4: Run** focused + full suite; analyze.
- [ ] **Step 5: Commit** `feat: playlists hide songs this device doesn't have; sync status in Account`

### Task 5: Remove home-network sync

**Files:**
- Delete: `lib/sync/{discovery,pairing_code,pairing_service,peer_repository,spake2,sync_auth,sync_client,sync_host,sync_progress,sync_responder,sync_runner,sync_server,file_transfer,merger,device_identity}.dart` (keep `device_identity.dart` only if something left still needs it — `originDevice` comes from `SyncStamp.deviceId`), `lib/ui/settings/sync/` (pair_sheets, sync_devices_page, sync_progress_card, clash_dialog), their tests, and router routes / providers / `main.dart` wiring for them; remove `_SyncSection` from Settings.
- Keep: `lib/sync/change_feed.dart`, `row_applier.dart`, `sync_row.dart`, `lib/data/sync_stamp.dart`, HLC, `SyncColumns`.
- Modify: `lib/data/tables.dart` + `lib/data/database.dart` (drop `Peers`; `schemaVersion` 9; `if (from < 9) await m.deleteTable('peers')`; regenerate drift code); remove packages only LAN sync used (mDNS, SPAKE2/crypto, shelf/server…) from pubspec if nothing else uses them; regenerate plugin registrants.
- Modify docs: `docs/manual-test-checklist.md` (remove pairing sections), `docs/ROADMAP.md` (step 2 done), release-notes line in `docs/releasing.md` or wherever release notes live: "Home-network sync is gone: sign in on every device to keep them in sync."
- Test: a migration test from schema 8 (with a `peers` row) to 9 keeps every other table's rows.

- [ ] **Step 1: Write the failing migration test.** **Step 2: Run** → FAIL.
- [ ] **Step 3: Delete and rewire.** `git grep -n "Peers\|pairing\|SyncRunner\|sync_devices"` finds nothing in lib/ and test/ afterwards.
- [ ] **Step 4: Run** `dart run build_runner build --delete-conflicting-outputs`, focused + full suite, analyze, and a debug APK build (`ANDROID_HOME=$HOME/Android/Sdk flutter build apk --debug`) since dependencies change.
- [ ] **Step 5: Commit** `refactor: remove home-network sync`
