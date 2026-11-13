# User Profile Page (SON-21) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `/profile` page holding your picture, name, email, listening
stats and account actions. It is opened from your picture in the Home
header (phone) or the title bar (desktop). Settings loses its Account
section.

**Architecture:**
- The stats content is cut out of `StatsPage` into a shared `StatsBody`.
- `AccountSection`'s logic moves into a new `ProfilePage`, which stacks:
  - the profile header;
  - `StatsBody`;
  - the account actions.
- Picture viewing and name editing are new widgets on the header.

**Tech Stack:** Flutter, Riverpod, go_router, flutter_test (`uiTest`,
`UiHarness`).

**Spec:** `docs/superpowers/specs/2026-11-13-profile-page-design.md`

## Global Constraints

- **Keep the existing keys** where the widget keeps its role, so the
  account tests move over with few edits: `account.username`,
  `account.email`, `account.signUp`, `account.logIn`, `account.logOut`,
  `account.delete`, `account.error`, `account.syncStatus`,
  `account.syncNow`, `account.lastSynced`, `shell.account`.
- **Existing text stays the same:**
  - islands "Picture removed" and "Username changed";
  - errors "That image is too big" and "Couldn't read that image";
  - the account error messages.
- **The username rules** are those of `UsernameField` / `usernameProblem`.
- Delete account keeps its confirmation, and Log out keeps its
  unsent-changes question.
- Run Flutter as `export PATH=$HOME/development/flutter/bin:$PATH`. Never
  boot the Android emulator.

## Review Focus

1. **A signed-out user follows a "Sign in" island** (rooms, player
   errors). Today they go to `/settings`. They must now land somewhere
   with Log in / Sign up: `/profile` shows the signed-out block.
   Covered in Task 5.
2. **Picture change or remove fails** (offline, too big). The error shows
   in the viewer, the viewer stays open, and the old picture stays.
   Covered in Task 3.
3. **Name edit:**
   - a taken name shows "That username is taken" and doesn't save;
   - the same name, or an invalid one, can't be saved;
   - Esc restores the old name;
   - while saving, the field is disabled.
   Covered in Task 4.
4. **Logging out from the profile page** returns it to the signed-out
   block without crashing. The stats stay, since they are local.
   Covered in Task 2.
5. **Phone width:** the header avatar sits before Settings, and the
   page fits at 360 px with no overflow. Covered in Task 5.

---

### Task 1: Shared stats content

**Files:**
- Modify: `lib/ui/stats/stats_page.dart`
- Test: `test/ui/stats_page_test.dart`

**Interfaces:**
- Produces: `class StatsBody extends ConsumerStatefulWidget { const
  StatsBody({super.key}); }`
  - It is the period picker plus the stats column (or the empty or error
    message).
  - It holds `_shown`, the stale dim and `_content`, moved from
    `_StatsPageState` unchanged.
  - It is a plain `Column(crossAxisAlignment: stretch)` with no scroll
    view of its own.
  - `StatsPage` becomes SafeArea → width cap → scroll → `[_Header(),
    StatsBody()]`.

- [ ] **Step 1: Write the failing test**
  `'StatsBody shows the stats inside another page'`:
  - Pump `Scaffold(body: SingleChildScrollView(child: StatsBody()))`
    with the same seeded listens the file's other tests use.
  - Expect `stats.chart` found and the text `'Top artists'` found.
  - Expect the text `'Your listening'` not found, since the header stays
    with `StatsPage`.
- [ ] **Step 2: Run, expect FAIL.**
  Run: `flutter test test/ui/stats_page_test.dart`
  Expected: compile error (`StatsBody` undefined).
- [ ] **Step 3: Implement** the split described above.
- [ ] **Step 4: Run, expect PASS.** All existing stats tests stay green.
- [ ] **Step 5: Commit**
  `refactor(stats): share the stats content as StatsBody (SON-21)`

### Task 2: Profile page with the account section moved in

**Files:**
- Create: `lib/ui/account/profile_page.dart`
- Modify:
  - `lib/router.dart`: add `/profile` beside `/settings`, inside the
    shell, built with `sharedAxisPage` + `PageSurface`.
  - `lib/ui/settings/settings_page.dart`: remove `AccountSection()`.
  - `lib/ui/account/account_section.dart`: its body becomes the parts
    below, and `AccountSection` goes away.
  - `lib/providers.dart:508`: change the doc comment to "for the profile
    page".
- Test:
  - `test/ui/account/account_ui_test.dart` and
    `test/ui/account/sync_ui_test.dart`: pump `/profile` →
    `ProfilePage` instead of `/settings` → `SettingsPage`. The
    `inSection` finder looks under `ProfilePage`.
  - New `test/ui/account/profile_page_test.dart`.

**Interfaces:**
- Produces:
  - `class ProfilePage extends ConsumerStatefulWidget`, key
    `Key('profile.page')`.
  - **Signed in,** top to bottom:
    - the header: back button when it can pop, `AccountAvatar(size: 96)`
      key `profile.avatar`, username `account.username`, email
      `account.email`;
    - `StatsBody()`;
    - an `'Account'` label;
    - `_SyncStatusLine` (moved as is);
    - Log out `account.logOut` and Delete account `account.delete`, in
      the error colour;
    - the error text `account.error`.
  - **Signed out:** today's signed-out block, unchanged: the text
    "Optional. Gives you a username and a picture.", Sign up and Log in.
    No stats.
  - `ProfilePage` owns `_run(action, done)`, `_logOut` and `_delete`,
    moved from `_AccountSectionState`, plus the `initState` `refresh()`.

- [ ] **Step 1: Write the failing tests** (`profile_page_test.dart`):
  - `'signed in: header, stats, then account actions in that order'`:
    - Expect the vertical order
      `account.username` < `stats.chart` (or `stats.empty`) <
      `account.syncStatus` < `account.logOut` < `account.delete`,
      by `tester.getTopLeft(...).dy`.
  - `'Settings has no Account section any more'`: pump `SettingsPage`,
    and find no `account.username` or `account.signUp`.
  - `'logging out returns the page to Sign up / Log in'`: log out
    (nothing unsent), then expect `account.signUp` found and no
    exception.
- [ ] **Step 2: Run, expect FAIL** (no `ProfilePage`).
  Run: `flutter test test/ui/account/profile_page_test.dart`
- [ ] **Step 3: Implement**
  - Move the code.
  - Remove the "Change username", "Change picture" and "Remove picture"
    action buttons from the actions row; Tasks 3 and 4 replace them.
  - In `account_ui_test.dart`, switch the pump to `/profile`. The test
    `'change username and change / remove picture…'` is rewritten in
    Tasks 3 and 4; for now mark it `skip: 'moves to Tasks 3–4'`.
- [ ] **Step 4: Run** `flutter test test/ui/account`. Expect PASS, except
  the one skipped test.
- [ ] **Step 5: Commit**
  `feat(profile): profile page holds the account section and stats
  (SON-21)`

### Task 3: Picture viewer

**Files:**
- Create: `lib/ui/account/picture_viewer.dart`
- Modify: `lib/ui/account/profile_page.dart` (avatar tap)
- Test: `test/ui/account/account_ui_test.dart`, replacing the picture half
  of the skipped test.

**Interfaces:**
- Consumes: `avatarPickerProvider`, `AccountService.setAvatar(...)` /
  `removeAvatar()`, and `maxAvatarSourceBytes`, the same calls
  `_changePicture` uses today.
- Produces: `Future<void> showPictureViewer(BuildContext context)`.
  - A dialog with `AccountAvatar(size: 240)`, then `FilledButton`
    "Change picture" `profile.changePicture`, then `TextButton`
    "Remove picture" `profile.removePicture`. Remove shows only when
    `profile.avatarPath != null`.
  - It has its own busy state and error text `profile.pictureError`.
  - It shows the same islands and errors as today.
  - It stays open on error and closes on success.
  - Tapping `profile.avatar` opens it.

- [ ] **Step 1: Write the failing tests**
  - `'tapping the picture opens it large with Change and Remove'`:
    - With no picture, expect `profile.changePicture` and no
      `profile.removePicture`.
    - Change (fake picker) closes it and shows "Picture changed". Use
      the island text `_changePicture` shows today; copy it exactly.
    - Reopen, and Remove now shows. Tapping it shows "Picture removed".
  - `'a picture too big shows the error and keeps the viewer open'`:
    expect `profile.pictureError` with text "That image is too big", and
    the dialog still open.
- [ ] **Step 2: Run, expect FAIL.**
  Run: `flutter test test/ui/account/account_ui_test.dart`
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** `feat(profile): tap your picture to change or
  remove it (SON-21)`

### Task 4: Inline name edit

**Files:**
- Create: `lib/ui/account/inline_username.dart`
- Modify: `lib/ui/account/profile_page.dart`
- Test: `test/ui/account/account_ui_test.dart`, replacing the username
  half of the skipped test and removing the skip.

**Interfaces:**
- Consumes: `UsernameField`, `normalizeUsername` and `usernameProblem`
  (existing), and `AccountService.changeUsername`.
- Produces: `class InlineUsername extends ConsumerStatefulWidget { const
  InlineUsername({required String username}); }`
  - It shows the name as text (`account.username`), and a tap swaps in a
    `UsernameField` (`account.newUsername`, autofocus).
  - Enter, or the check `IconButton` (`profile.saveUsername`), saves when
    `_canSave` holds (same rule as the dialog).
  - Esc or the close button cancels. Losing focus while not busy also
    cancels.
  - On success: the island "Username changed" and back to text.
  - On error: text `account.dialogError` under the field.
  - `showChangeUsernameDialog` stays in `account_dialogs.dart` only if
    something else uses it. Otherwise delete it.

- [ ] **Step 1: Write the failing tests**
  - `'tap the name to edit it; Enter saves'`: the island "Username
    changed", and `account.username` shows the new name.
  - `'Esc restores the old name without saving'`: the fake account
    service records no `changeUsername`.
  - `'a taken name cannot be saved'`: with the fake, mark the name taken.
    `profile.saveUsername` is disabled, and Enter does nothing.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test test/ui/account`. Expect PASS with no
  skips left.
- [ ] **Step 5: Commit** `feat(profile): tap your name to change it
  (SON-21)`

### Task 5: Entry points

**Files:**
- Modify:
  - `lib/ui/account/avatar.dart` (`AccountButton`)
  - `lib/ui/home/home_page.dart` (`_Header`, phone)
  - `lib/ui/room/room_panel.dart:118`
  - `lib/ui/room/join_room_dialog.dart:24`
  - `lib/ui/shell/player_error_islands.dart:85`
- Test:
  - `test/ui/shell_test.dart`: update the `shell.account` tests at about
    lines 698–740.
  - `test/ui/home_page_test.dart`

**Interfaces:**
- **`AccountButton`:**
  - Signed in, `context.go('/profile')`.
  - Signed out, `showAuthScreen(context, AuthStart.logIn)`.
  - The tooltip stays.
- **Home `_Header`:** when `showSettings` (phone), add `AccountButton()`
  just before the Settings button.
- **"Sign in" links:** the room island, the room panel, the join dialog
  and the player-error island go to `/profile` instead of `/settings`.
  `/profile` shows Sign up / Log in when signed out.
  - `import_dialog.dart`'s "Open Settings" stays: it is about the yt-dlp
    binary, not the account.

- [ ] **Step 1: Write the failing tests**
  - In `shell_test.dart`, change the expectation to
    `router.state.uri.path == '/profile'` when signed in. Signed out, the
    auth screen opens (find the `AuthScreen` type).
  - `home_page_test.dart`: `'the phone header has your picture before
    Settings'`.
    - At 400 px width, find `shell.account`, and its `dx` is less than
      `home.settings`'s `dx`.
    - Tapping it while signed in lands on `/profile`.
    - At 360 px, no overflow exception.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test test/ui`, then the full
  `flutter test` and `flutter analyze`. Expect all green.
- [ ] **Step 5: Commit** `feat(profile): open your profile from your
  picture (SON-21)`
