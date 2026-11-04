# Island Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace every Material snack bar in Songies with a black "island" pill that pops up from behind the player bar / mini player.

**Architecture:** A root `IslandHost` (in `SongiesApp`'s `MaterialApp.router` builder, so it sits above the navigator and therefore above sheets, menus and dialogs) owns an `IslandController` and draws one island. Shells mark the thing the island emerges from with an `IslandAnchor`. Call sites use `Islands.of(context).show(...)`, which replaces `PageSnackBars`.

**Tech Stack:** Flutter, Riverpod (existing), `flutter_test` + `fake_async` timing through the existing `uiTest`/`settle` helpers.

**Spec:** `docs/superpowers/specs/2026-11-04-island-notifications-design.md`

Flutter is at `~/development/flutter/bin` (not on PATH): run commands with
`export PATH=$HOME/development/flutter/bin:$PATH` first.

## Global Constraints

- Island: black (`Color(0xFF000000)`) in every theme; soft drop shadow; outline white at 8–12 % opacity.
- Height ≈ 38 px for one line; fully rounded ends; padding ≈ 8 px; white text; at most **2 lines** then ellipsis (pill grows taller for 2 lines).
- Max width ≈ 420 px on wide layouts; screen width − 32 px on phones.
- Leading: song cover 22 px, radius 4 (`Artwork`) when about one song; else icon — check (success), warning (failure), info (info).
- Action: right side, theme accent colour (`SongiesColors.accent`), bold.
- In: from behind the anchor, scale ≈ 0.6 → 1, rising, fading in, ease-out, 250–300 ms. Out: reverse. Reduced motion (`MediaQuery.disableAnimations`): fade only.
- One island at a time; a new message morphs the current island (size + content animate), no stacking or queueing.
- Default duration 4 s; call sites that pass a duration keep it (playlist page "Added to queue": 2 s).
- Hover pauses the countdown (desktop); leaving restarts it. Tap/click on the island (not its action) dismisses. Swipe down dismisses. Action runs then the island closes.
- Message is announced to screen readers.
- Island floats over content, never pushes it, never covers player controls or the phone banner's buttons.
- Confirmation `AlertDialog`s are untouched.

## Review Focus

1. A message raised while a bottom sheet is open (Add to playlist failure) must be visible above the sheet — test in Task 4.
2. A message raised just before the page that raised it is popped (e.g. `snacks` captured before an `await`, then navigation) must still show and time out normally — test in Task 2.
3. A long message (player "Stopped — 3 songs in a row couldn't play. <reason>" + Sign in) shows 2 lines, ellipsis, and the action stays visible and tappable — test in Task 2.
4. Messages fired in quick succession (consecutive skip notices, settings rescan of several folders) leave exactly one island showing the newest, with a fresh full duration — test in Task 1 and Task 2.
5. The anchor moving while an island shows (mini player appears, window resized) keeps the island just above the anchor's new top — test in Task 2.

---

### Task 1: Island model and controller

**Files:**
- Create: `lib/ui/island/island_controller.dart`
- Test: `test/ui/island/island_controller_test.dart`

**Interfaces:**
- Produces:
  - `enum IslandKind { success, failure, info }`
  - `class IslandAction { const IslandAction({required String label, required VoidCallback onPressed}); }`
  - `class IslandMessage { const IslandMessage({required String text, IslandKind kind = IslandKind.info, Track? song, IslandAction? action, Duration duration = IslandMessage.defaultDuration}); static const Duration defaultDuration = Duration(seconds: 4); }` (`Track` from `lib/data/database.dart`; `song` supplies `artworkRef` and `id` as the `Artwork` seed)
  - `class IslandController extends ChangeNotifier` with `IslandMessage? get current`, `int get serial` (bumps on every `show`, so the view can tell a replacement from a rebuild), `void show(IslandMessage m)`, `void dismiss()`, `void pause()`, `void resume()`, `void runAction()` (calls the current action's `onPressed`, then `dismiss()`), `void dispose()`.

- [ ] **Step 1: Write the failing tests** (use `fakeAsync` from `package:fake_async`)

```dart
test('show sets current and dismisses after its duration', ...);
  // show(text 'Hi'); elapse 3999 ms -> current?.text == 'Hi'; elapse 1 ms -> current == null
test('a new message replaces the current one and restarts the timer', ...);
  // show 'A' (4 s); elapse 3 s; show 'B'; serial increased; elapse 3 s -> current?.text == 'B'; elapse 1 s -> null
test('a custom duration is kept', ...);
  // show duration 2 s -> null after 2 s
test('pause holds the message; resume restarts the full duration', ...);
  // show; elapse 3 s; pause; elapse 10 s -> still shown; resume; elapse 3999 ms -> shown; elapse 1 ms -> null
test('runAction calls the action then dismisses', ...);
test('dismiss clears and notifies listeners', ...);
test('five messages in a row leave only the last', ...);
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/ui/island/island_controller_test.dart`
Expected: FAIL (file/classes missing).

- [ ] **Step 3: Implement the types above in `lib/ui/island/island_controller.dart`**

One `Timer?`; `show` cancels it and starts a new one for `m.duration`; `pause` cancels; `resume` starts a full `current.duration` again. Notify listeners on every change.

- [ ] **Step 4: Run the tests to see them pass**

Run: `flutter test test/ui/island/island_controller_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/island/island_controller.dart test/ui/island/island_controller_test.dart
git commit -m "feat: island message controller"
```

### Task 2: Island host, anchor and view

**Files:**
- Create: `lib/ui/island/island_host.dart` (`IslandHost`, `IslandAnchor`, `Islands`)
- Create: `lib/ui/island/island_view.dart` (the pill itself)
- Test: `test/ui/island/island_host_test.dart`

**Interfaces:**
- Consumes: Task 1 types.
- Produces:
  - `class IslandHost extends StatefulWidget { const IslandHost({required Widget child}); }` — a `Stack` of `child` and the island layer; owns one `IslandController`; provides it to descendants through a private `InheritedWidget`.
  - `class IslandAnchor extends StatefulWidget { const IslandAnchor({required Widget child}); }` — marks the widget the island emerges from. Registers with the nearest host on mount, unregisters on dispose; after each layout (post-frame) it reports its global rect, and the host rebuilds when the rect changes. Only the most recently mounted anchor is used.
  - `class Islands { static Islands of(BuildContext context); void show(String text, {IslandKind kind = IslandKind.info, Track? song, IslandAction? action, Duration duration = IslandMessage.defaultDuration}); void clear(); }` — `of` throws a `FlutterError` naming `IslandHost` when there is none. The returned object holds the controller, so it stays usable after `context` unmounts (same contract as `PageSnackBars.of`).

**Placement rule** (the host computes this at show time and on every rebuild):
- If an anchor is registered, mounted, and `ModalRoute.of(anchorContext)?.isCurrent != false`: the island's bottom edge rests 10 px above the anchor's top; it is clipped (`ClipRect`) to the area above the anchor's top, so while scaling up from below it appears to come out from behind the anchor.
- Otherwise (no anchor, keyboard hid it, or a sheet / menu / dialog / full-screen player route is above it): the island's bottom edge rests 16 px above `max(MediaQuery.viewInsets.bottom, MediaQuery.viewPadding.bottom)`, clipped to the area above that line (so it rises from the screen's bottom edge or the keyboard's top).
- Always horizontally centred on the host's width. Max width 420 when the host is ≥ 600 px wide, else host width − 32.

**View:** `AnimatedSize` + `AnimatedSwitcher` keyed on `serial` for the morph; entry/exit as in Global Constraints (scale from bottom-centre alignment + slide down by its own height + opacity); fade only when `MediaQuery.disableAnimations`. `MouseRegion` → `pause`/`resume`; `GestureDetector` `onTap` → `dismiss`, `onVerticalDragEnd` with positive velocity → `dismiss`; the action is a `TextButton`-like target whose tap does not bubble to the island's `onTap`. Wrap text in `Semantics(liveRegion: true)`.

- [ ] **Step 1: Write the failing widget tests**

Harness: `MaterialApp(builder: (_, c) => IslandHost(child: c!), home: Scaffold(body: Column(children: [Expanded(child: Builder(...button that calls Islands.of(context).show...)), IslandAnchor(child: SizedBox(key: Key('bar'), height: 72))])))` at 1280×800.

```dart
uiTest('an island appears centred just above the anchor', ...);
  // tap; settle; island = find.byKey(Key('island'));
  // expect(getRect(island).bottom, closeTo(getRect(bar).top - 10, 1));
  // expect(getRect(island).center.dx, closeTo(640, 1));
uiTest('it is black with white text in a light theme too', ...);
  // theme brightness light; the island's decoration colour == Color(0xFF000000)
uiTest('a song message shows the cover; a failure shows a warning icon', ...);
  // find.descendant(of: island, matching: find.byType(Artwork)) findsOne;
  // kind failure -> find.byIcon(Icons.warning_amber_rounded) findsOne
uiTest('it goes away after 4 s', ...);
uiTest('tapping it dismisses it; tapping its action runs it and dismisses', ...);
uiTest('swiping it down dismisses it', ...);  // tester.drag(island, Offset(0, 60))
uiTest('hovering pauses the countdown', ...);
  // TestGesture mouse addPointer + moveTo island centre; pump 10 s -> still there; moveTo (0,0); pump 4 s -> gone
uiTest('a long message wraps to two lines and keeps its action', ...);
  // text = 'Stopped — 3 songs in a row couldn\'t play. ' * 4, action Sign in;
  // island height > 38 and < 70; find.text('Sign in') hit-testable; tap it -> callback ran
uiTest('three quick messages show only the last', ...);
  // find.byKey(Key('island')) findsOneWidget; find.text('C') findsOne; find.text('A') findsNothing
uiTest('it stays above the anchor when the anchor moves', ...);
  // show; then rebuild with anchor height 72 -> 140; settle; island bottom ≈ new bar top - 10
uiTest('with no anchor it rises from the screen bottom', ...);
uiTest('a message survives the page that sent it being popped', ...);
  // push route B; capture Islands.of(ctxB); pop B; then show via captured -> shown, gone after 4 s
uiTest('reduced motion fades without scaling', ...);
  // MediaQuery(disableAnimations: true); mid-animation find.byType(ScaleTransition) under island -> none or scale 1
uiTest('the message is a live region for screen readers', ...);
  // tester.getSemantics(find.text('Hi')) has flag isLiveRegion
uiTest('Islands.of without a host throws a FlutterError naming IslandHost', ...);
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/ui/island/island_host_test.dart`
Expected: FAIL (missing classes).

- [ ] **Step 3: Implement `IslandHost`, `IslandAnchor`, `Islands` in `lib/ui/island/island_host.dart` and the pill in `lib/ui/island/island_view.dart`** per the placement rule and view notes above. Give the pill `key: Key('island')`. Icons: `Icons.check_circle_rounded`, `Icons.warning_amber_rounded`, `Icons.info_outline_rounded`.

- [ ] **Step 4: Run the tests to see them pass**

Run: `flutter test test/ui/island/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/island test/ui/island
git commit -m "feat: the island: host, anchor and pill"
```

### Task 3: Put the host and anchors in the app

**Files:**
- Modify: `lib/app.dart:88` (builder: wrap in `IslandHost`, outermost inside `MotionScope`/`_ThemeScope` so it gets the theme and motion)
- Modify: `lib/ui/shell/desktop_shell.dart` (wrap the `PlayerBar` in `IslandAnchor`)
- Modify: `lib/ui/shell/phone_shell.dart:54-80` (wrap the whole bottom `Column` — banner, indicator, mini player, nav — in `IslandAnchor`; it is absent while the keyboard is open, which gives the keyboard rule for free)
- Modify: `test/helpers/ui_harness.dart:321` (same builder wrap so shell tests have a host)
- Test: `test/ui/island/island_placement_test.dart`

**Interfaces:**
- Consumes: `IslandHost`, `IslandAnchor`, `Islands` (Task 2).

- [ ] **Step 1: Write the failing tests** (use the router harness like `test/ui/favorite_star_test.dart`)

```dart
uiTest('desktop: the island sits just above the player bar', ...);
  // 1280x800, play a track; Islands.of(any page element).show('Hi');
  // island bottom ≈ getRect(find.byType(PlayerBar)).top - 10
uiTest('phone: the island sits above the whole bottom stack', ...);
  // 400x800 with downloads banner visible (downloadsBannerVisibleProvider override true) and a track playing;
  // island bottom ≈ getRect(find.byType(DownloadsBanner)).top - 10
uiTest('phone with nothing playing: above the bottom nav', ...);
uiTest('full-screen player open: the island rises from the screen bottom', ...);
  // openNowPlaying; show; island bottom ≈ 800 - 16
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/ui/island/island_placement_test.dart`
Expected: FAIL (no host in the app).

- [ ] **Step 3: Make the four modifications listed under Files.**

- [ ] **Step 4: Run the tests and the shell tests**

Run: `flutter test test/ui/island/ test/ui/shell_test.dart test/ui/shell/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/app.dart lib/ui/shell test/helpers/ui_harness.dart test/ui/island/island_placement_test.dart
git commit -m "feat: the island lives above the app and rises from the player bar"
```

### Task 4: Move every message to the island

**Files:**
- Modify: every file using `PageSnackBars` / `showPageSnackBar` (`grep -rln "PageSnackBars\|showPageSnackBar\|SnackBarAction" lib` — 22 files, 42 call sites), including `lib/ui/shell/player_error_snacks.dart`.
- Delete: `lib/ui/widgets/page_snack_bar.dart`
- Modify tests: `test/ui/settings_test.dart:216`, `test/update/update_controller_test.dart:487`, and any test that now fails for want of an `IslandHost` (add `builder: (_, c) => IslandHost(child: c!)` to its `MaterialApp`).
- Test: `test/ui/island/island_messages_test.dart`

**Interfaces:**
- Consumes: `Islands.of(context).show(String, {kind, song, action, duration})`, `IslandAction`, `IslandKind` (Tasks 1–2).

**Mapping for each call site:**
- `snacks.show(content: Text(x))` → `islands.show(x, kind: …)`; drop `maxLines` arguments; keep any `duration`.
- `..clear()..show(...)` → just `show` (it replaces).
- `SnackBarAction(label, onPressed)` → `IslandAction(label:, onPressed:)` (3 sites: player errors "Sign in", playlist "Undo", YTM "Open").
- `kind`: `failure` for any text starting "Couldn't", errors from `failure.message`, `ytErrorUserMessage…`, `folderPickFailureMessage`, `playerErrorMessage`, `playerNoticeMessage`, "No log yet", "No browser profile found", "The download failed."; `success` for "Added…", "Removed…", "…imported", "…exported", "Log saved", "Copied", "Downloading…", "YouTube recommendations reset", "Theme imported/exported"; `info` otherwise.
- `song:` where the message is about one library `Track` in hand: playlist page "Removed ${track.title}" (`removed.track`).
- Rename local variables `snacks` → `islands`; rename `PlayerErrorSnacks` → `PlayerErrorIslands` (file `player_error_islands.dart`, update both shells and `test/ui/shell/player_error_snacks_test.dart` → `player_error_islands_test.dart`).
- Settings "rescan all" used to queue one snack bar per failed folder; now the last one wins. Update `test/ui/settings_test.dart` to expect only `"Couldn't scan Rock"` after the rescan (drop the `hideCurrentSnackBar` step).

- [ ] **Step 1: Write the failing tests**

```dart
uiTest('removing a song from a playlist shows an island with its cover and Undo', ...);
  // playlist page; remove 'Song one'; island contains find.text('Removed Song one'), an Artwork, 'Undo'; tap Undo -> song back
uiTest('a player error shows a failure island with Sign in for age-restricted songs', ...);
uiTest('an Add to playlist failure shows above the open sheet', ...);
  // open add_to_playlist_sheet; make create fail; island hit-testable while sheet route is current;
  // island bottom ≈ screen bottom - 16
uiTest('no SnackBar is ever shown', ...);
  // drive: playlist remove, theme export; expect(find.byType(SnackBar), findsNothing)
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/ui/island/island_messages_test.dart`
Expected: FAIL (still snack bars).

- [ ] **Step 3: Migrate every call site per the mapping, delete `page_snack_bar.dart`.**

Check: `grep -rn "SnackBar\|PageSnackBars\|showPageSnackBar\|ScaffoldMessenger" lib` prints nothing.

- [ ] **Step 4: Run the whole suite and the analyzer**

Run: `flutter analyze lib test && flutter test`
Expected: `No issues found!`; all tests pass (the stats "80,000 listens under 500 ms" timing test can flake under full-suite load; re-run it alone if it is the only failure).

- [ ] **Step 5: Commit**

```bash
git add -A lib test
git commit -m "feat: every message shows as an island"
```

### Task 5: "Added to queue" from the song menu

**Files:**
- Modify: `lib/ui/widgets/song_menu.dart:259-260` (`SongMenuAction.addToQueue`)
- Test: `test/ui/song_menu_test.dart`

**Interfaces:**
- Consumes: `Islands` (Task 2).

- [ ] **Step 1: Write the failing test**

```dart
uiTest('Add to queue from the song menu shows an island with the song', ...);
  // open song menu on 'Song one'; tap 'Add to queue'; settle;
  // find.text('Added to queue') findsOne; island contains an Artwork; kind success (check not needed: cover replaces icon)
```

- [ ] **Step 2: Run it to see it fail**

Run: `flutter test test/ui/song_menu_test.dart`
Expected: FAIL (no message).

- [ ] **Step 3: After `player.addToQueue([t])`, show `'Added to queue'`, `kind: IslandKind.success`, `song: t`.** Capture `Islands.of(context)` before the first `await` in that handler, like the existing `snacks`.

- [ ] **Step 4: Run it to see it pass**

Run: `flutter test test/ui/song_menu_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/widgets/song_menu.dart test/ui/song_menu_test.dart
git commit -m "feat: Add to queue from a song's menu says so"
```
