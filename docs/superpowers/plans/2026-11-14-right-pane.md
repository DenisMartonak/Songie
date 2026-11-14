# Right Pane Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the desktop lyrics pane and the player bar's room button with one right pane (Friends with Listen together, Lyrics, or Queue) that closes to a strip of friends' faces.

**Architecture:** One remembered open flag (device-local setting) plus a session-only content choice drive a single `RightPane` that the desktop shell places where `LyricsPanel` sits today. Closed, the shell shows `RightPaneStrip` instead. The room dialog's body becomes embeddable; the Friends page's person row becomes shared.

**Tech Stack:** Flutter, Riverpod (`Notifier`, `StreamProvider`), go_router, drift-backed `SettingsRepository`. Tests: `flutter_test` with `UiHarness` / `uiTest` and `RoomRig`.

**Spec:** `docs/superpowers/specs/2026-11-14-right-pane-design.md`

Run Flutter as `export PATH=$HOME/development/flutter/bin:$PATH` first. Never boot the Android emulator.

## Global Constraints

- Desktop shell only (`DesktopShell`, width ≥ `phoneBreakpoint`). The phone layout, its Home header `RoomButton` and the room bottom sheet don't change.
- Open pane width: `RightPane.width = 320` (was `LyricsPanel.width`), plus the 8 px gap.
- Strip width: `RightPaneStrip.width = 40`, plus the 8 px gap. Faces 24 px.
- Open by default (`fallback: true`); only `open` is remembered, under `kRightPaneOpen = 'right_pane_open'`. Content always starts as Friends.
- Pane and strip are wrapped in `ExcludeFocus` (Space must keep toggling play).
- Open/close animate with `AnimatedSize` over `Motion.of(context).standard`, `Motion.standardCurve`; none at all under reduced motion (as `LyricsPanel` does).
- Copy: header titles `Friends`, `Lyrics`, `Queue`; X tooltip `Close`; strip tooltip `Show friends`; links `Find friends` and `N requests` (`1 request` singular).
- Now Playing keeps its header `RoomButton` and the dialog.

## Review Focus

1. **A stored "closed" at startup:** the pane must not flash open and animate shut. Until the setting has loaded, nothing is drawn on the right; the first known value appears without animation. (Task 1 and Task 4 tests.)
2. **Lyrics lookups:** lyrics must not be fetched while the pane shows Friends or is closed, only while it shows Lyrics. (Task 4 test, adapted from "closed by default: no panel and no lookups".)
3. **Space after clicking in the pane or strip:** Space still toggles play. (Task 4 test.)
4. **The activity lease:** leaving Friends (to Lyrics, to Queue, or closing) releases the one-minute watch; coming back takes it again. (Task 3 test.)
5. **Signing out with the pane open:** friends and the room section give way to the sign-in line without errors. (Task 3 test.)

---

### Task 1: Right pane state

**Files:**
- Create: `lib/ui/shell/right_pane_state.dart`
- Modify: `lib/data/settings_repository.dart` (add the key)
- Test: `test/ui/shell/right_pane_state_test.dart`

**Interfaces:**
- Produces:
  - `const kRightPaneOpen = 'right_pane_open';` in `settings_repository.dart`, documented device-local.
  - `enum RightPaneContent { friends, lyrics, queue }`
  - `final rightPaneOpenProvider = Provider<bool?>` — the stored flag, `null` until loaded (from a private `StreamProvider<bool>` over `watchBool(kRightPaneOpen, fallback: true)`).
  - `final rightPaneContentProvider = NotifierProvider<RightPaneContentNotifier, RightPaneContent>` — session only, starts `friends`.
  - `final rightPaneProvider = Provider<RightPaneController>` with:
    - `Future<void> close()` → stores `false`;
    - `Future<void> showFriends()` → content `friends`, stores `true`;
    - `Future<void> toggle(RightPaneContent c)` → if open and showing `c` (and `c != friends`), content `friends`; else content `c`, stores `true`.

`lyricsPanelOpenProvider` (`providers.dart:201-210`) stays until Task 4, which rewires its readers (`desktop_shell.dart`, `player_bar.dart`, `lyrics_panel.dart`) and deletes it.

- [ ] **Step 1: Write the failing tests** in `right_pane_state_test.dart`, with a `ProviderContainer` over a test database's `SettingsRepository` (see `test/helpers/test_db.dart`):
  - `'open by default, on Friends'`: after the stream loads, `rightPaneOpenProvider` is `true`, content `friends`.
  - `'null until the setting has loaded'`: read synchronously right after creating the container → `null`.
  - `'close is remembered'`: `close()`; a new container on the same DB reads `false`.
  - `'toggle lyrics opens on lyrics; again goes back to friends, still open'`.
  - `'toggle queue from closed opens on queue'`.
  - `'showFriends opens on friends'`.
  - `'content is not remembered'`: toggle lyrics, new container → content `friends`.
- [ ] **Step 2:** Run `flutter test test/ui/shell/right_pane_state_test.dart`. Expected: FAIL (file not found / undefined names).
- [ ] **Step 3:** Implement `right_pane_state.dart` and the key.
- [ ] **Step 4:** Run the test again. Expected: PASS. Run `flutter analyze`. Expected: no issues.
- [ ] **Step 5: Commit** `feat(shell): right pane state (SON-40)`.

---

### Task 2: Embeddable room panel and shared friend row

**Files:**
- Modify: `lib/ui/room/room_panel.dart`
- Create: `lib/ui/friends/friend_row.dart` (from `_PersonRow` in `friends_page.dart:199-258`)
- Modify: `lib/ui/friends/friends_page.dart` (use `FriendRow`)
- Test: `test/ui/room_panel_test.dart`

**Interfaces:**
- Produces:
  - `RoomPanel({bool embedded = false, Key? key})`. Embedded: no `SingleChildScrollView` (a plain `Column`, `mainAxisSize: min`), padding `EdgeInsets.fromLTRB(16, 12, 16, 12)`, the title row at 15 px instead of 18. `_signIn` pops the navigator only when not embedded. Not embedded: unchanged.
  - `FriendRow({required FriendUser user, NowPlaying? listening, List<Widget> actions = const [], VoidCallback? onTap, double avatarSize = 44, bool chevron = true, Key? key})` — today's `_PersonRow` with the avatar size and chevron made parameters. The page passes nothing new.

- [ ] **Step 1: Write the failing tests** in `room_panel_test.dart`, pumping `Scaffold(body: ListView(children: [RoomPanel(embedded: true)]))` (inside `RoomIslands`):
  - `'embedded in a list: idle shows Start a room and Join a room'`.
  - `'embedded, signed out: Sign in goes to /profile and nothing is popped'`: tap Sign in, expect `Profile page`.
- [ ] **Step 2:** Run `flutter test test/ui/room_panel_test.dart`. Expected: the new tests FAIL (unknown `embedded` parameter).
- [ ] **Step 3:** Add `embedded` to `RoomPanel`; move `_PersonRow` to `FriendRow` and use it in `friends_page.dart`.
- [ ] **Step 4:** Run `flutter test test/ui/room_panel_test.dart test/ui/friends`. Expected: PASS (the Friends page tests unchanged).
- [ ] **Step 5: Commit** `refactor(room): embeddable room panel; shared friend row (SON-40)`.

---

### Task 3: The Friends view of the pane

**Files:**
- Create: `lib/ui/shell/right_pane_friends.dart`
- Test: `test/ui/shell/right_pane_friends_test.dart`

**Interfaces:**
- Consumes: `RoomPanel(embedded: true)`, `FriendRow` (Task 2); `friendsStateProvider`, `friendsServiceProvider` (`watchClosely()` / `stopWatching(lease)`), `nowProvider`, `accountStateProvider`, `joinRoomAsking`.
- Produces: `class RightPaneFriends extends ConsumerStatefulWidget` (`const RightPaneFriends({Key? key})`), a `ListView` keyed `rightPane.friends`.

Behaviour, top to bottom: `RoomPanel(embedded: true)`; then, signed in only: a `Friends` section label; one `FriendRow` per `state.friends` (`avatarSize: 36`, `chevron: false`, key `rightPane.friend.<id>`), `listening` as on the Friends page, a Join action (key `rightPane.join.<id>`) when `state.listening(id, now)` and `activity[id].roomCode != null`, calling `joinRoomAsking(context, ProviderScope.containerOf(context), code)`; tap → `context.push('/profile/friends/<id>')`. Then `N requests` (key `rightPane.requests`) when `state.incoming.isNotEmpty`, and `Find friends` (key `rightPane.findFriends`) when `state.loaded && state.friends.isEmpty`; both `context.push('/profile/friends')`. Before `state.loaded`, no friend rows and no links. Signed out: only the room panel (its sign-in line). Takes a `watchClosely()` lease in `initState` while signed in, releases it in `dispose` and on sign-out.

- [ ] **Step 1: Write the failing tests** (use `FakeFriendsBackend` / `FakeActivityBackend` from `test/helpers`, as `friends_page` tests do):
  - `'room on top, then friends with what they play and Join'`: a friend hosting room `ABCD2345` shows `♪ title · artist` and `rightPane.join.<id>`; another not listening shows no Join.
  - `'Join asks to join the friend room'`: tap Join → the room service was asked to join `ABCD2345` (check the rig/backend call).
  - `'a friend opens their page'`: tap the row → route `/profile/friends/<id>`.
  - `'requests and find friends links'`: 2 incoming → text `2 requests`; 1 → `1 request`; loaded with none → `Find friends`; not loaded → neither.
  - `'holds a close watch while shown, released when gone'`: the service's close-watch count is 1 while mounted, 0 after the widget is removed.
  - `'signing out leaves only the sign-in line'`: sign out while shown → no `rightPane.friend.*`, `kRoomSignInText` shown, close-watch count 0, no exception.
- [ ] **Step 2:** Run `flutter test test/ui/shell/right_pane_friends_test.dart`. Expected: FAIL (missing file).
- [ ] **Step 3:** Implement `RightPaneFriends`. If `FriendsService` exposes no watch count, add `@visibleForTesting int get closeWatches`.
- [ ] **Step 4:** Run the test again. Expected: PASS.
- [ ] **Step 5: Commit** `feat(shell): friends and listen together in the right pane (SON-40)`.

---

### Task 4: The right pane in the shell, and the player bar

**Files:**
- Create: `lib/ui/shell/right_pane.dart`
- Delete: `lib/ui/lyrics/lyrics_panel.dart`
- Modify: `lib/ui/shell/desktop_shell.dart:170, 226-299` (read `rightPaneOpenProvider`; `RightPane.width` for the squeeze/overlay maths; place `RightPane` where `LyricsPanel` was)
- Modify: `lib/ui/shell/player_bar.dart:395-440` (`_QueueAndVolume`)
- Modify: `lib/providers.dart` (delete `lyricsPanelOpenProvider`)
- Test: rename `test/ui/lyrics_panel_test.dart` → `test/ui/right_pane_test.dart` and adapt; update `test/ui/player_bar_test.dart`, `test/ui/shell_test.dart`, `test/ui/room_faces_test.dart`, `test/ui/now_playing/now_playing_faces_test.dart`, `test/ui/shell/phone_remote_test.dart` where they use `lyricsPanelOpenProvider`, `playerBar.queue` or the player bar's `room.button`.

**Interfaces:**
- Consumes: Task 1 providers; `RightPaneFriends` (Task 3); `LyricsView(density: LyricsDensity.compact)`; `NowPlayingQueue`.
- Produces:
  - `class RightPane extends ConsumerWidget` with `static const double width = 320`. When `rightPaneOpenProvider == true`: padded 8 right/bottom, `SizedBox(key: Key('rightPane'), width: 320)`, rounded `colors.background` surface, `ExcludeFocus`; a header row with the title (key `rightPane.title`) and an X `IconButton` (key `rightPane.close`, tooltip `Close`) calling `close()`; below, the content for `rightPaneContentProvider`. When `false`: `SizedBox.shrink()` (Task 5 puts the strip here). When `null`: `SizedBox.shrink()` with no animation. `AnimatedSize` only once the value is known.
  - Player bar right end: Lyrics (key `playerBar.lyrics`) → `toggle(lyrics)`, lit when open on lyrics; Queue (key `playerBar.queue`) → `toggle(queue)`, lit the same way, `selectedIcon` `Icons.queue_music_rounded` in accent; `DevicesButton`; volume. `RoomButton` removed from the bar. The cover/title still open Now Playing.
  - Desktop shell: `panelOpen` becomes `ref.watch(rightPaneOpenProvider) == true`.

- [ ] **Step 1: Adapt and write the failing tests** in `right_pane_test.dart`:
  - `'open by default on Friends, 320 px, right of the main pane'` (was `toggles a compact panel…`).
  - `'Lyrics shows lyrics in the pane; Lyrics again goes back to Friends'`, with the lit-icon checks from `the button shows the open state`.
  - `'Queue shows the queue in the pane, and does not open Now Playing'`.
  - `'the X closes the pane, whatever it shows; reopening keeps working'`.
  - `'no lyrics lookups while the pane shows Friends or is closed'` (Review Focus 2; was `closed by default: no panel and no lookups`): the fake lyrics service records no request until Lyrics is shown.
  - `'a stored closed pane never shows at startup'` (Review Focus 1): seed `kRightPaneOpen = '0'`, pump the app, pump each frame of the first 500 ms; `find.byKey(Key('rightPane'))` finds nothing every frame.
  - `'Space toggles play after clicking the X and the Lyrics button'` (Review Focus 3).
  - Keep `stays open across tabs`, `opens and closes over Motion.standard`, `opens at once under reduced motion` and the narrow-window squeeze/overlay group, switched to the pane.
  - In `player_bar_test.dart`: `'the player bar has Lyrics, Queue and Devices, and no room button'`.
- [ ] **Step 2:** Run `flutter test test/ui/right_pane_test.dart test/ui/player_bar_test.dart`. Expected: FAIL.
- [ ] **Step 3:** Implement `RightPane`, rewire the shell and the player bar, delete `lyrics_panel.dart` and `lyricsPanelOpenProvider`, and update the other tests listed under Files.
- [ ] **Step 4:** Run `flutter analyze` and `flutter test`. Expected: no issues; all pass (the stats timing test can fail under full-suite load; rerun it alone).
- [ ] **Step 5: Commit** `feat(shell): one right pane for friends, lyrics and queue (SON-40)`.

---

### Task 5: The strip

**Files:**
- Create: `lib/ui/shell/right_pane_strip.dart`
- Modify: `lib/ui/shell/right_pane.dart` (closed → strip), `lib/ui/shell/desktop_shell.dart` (the strip is always beside the page, never overlaid, and doesn't squeeze the sidebar)
- Test: `test/ui/shell/right_pane_strip_test.dart`

**Interfaces:**
- Consumes: `rightPaneProvider.showFriends()` (Task 1), `friendsStateProvider`, `nowProvider`, `roomStatusProvider`, `PersonAvatar(name:, url:, size: 24)`.
- Produces: `class RightPaneStrip extends ConsumerWidget`, `static const double width = 40`, key `rightPane.strip`. Rounded `colors.background` surface, scrollable column: the people icon (`Icons.group_rounded`; accent with a `Badge` count while hosting or guesting, as `RoomButton` does), then a face per `state.friends` (key `rightPane.strip.<id>`, tooltip the username) with a green dot while `state.listening(id, now)`. Signed out: the icon only. The whole strip is one target: `MouseRegion(cursor: SystemMouseCursors.click)` + tap → `showFriends()`, tooltip `Show friends`. `ExcludeFocus`.

- [ ] **Step 1: Write the failing tests:**
  - `'closing shows the strip with each friend face, a dot for those listening'`.
  - `'in a room the strip shows the count'` (use `RoomRig` hosting with one guest → badge `2`).
  - `'clicking the strip opens the pane on Friends, even after Lyrics was shown'`.
  - `'the strip shows the hand cursor'` (as in `player_bar_test.dart`'s cursor test).
  - `'a narrow window keeps the strip beside the page and the sidebar expanded'`: 900 px wide, pane closed → strip present, `Sidebar` expanded, no overlay.
  - `'signed out: only the people icon'`.
- [ ] **Step 2:** Run `flutter test test/ui/shell/right_pane_strip_test.dart`. Expected: FAIL.
- [ ] **Step 3:** Implement the strip and the shell placement (strip width `40 + 8` in the layout, outside the overlay branch).
- [ ] **Step 4:** Run `flutter analyze` and `flutter test`. Expected: no issues; all pass.
- [ ] **Step 5: Commit** `feat(shell): the right pane closes to a strip of faces (SON-40)`.
