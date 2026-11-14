# Settings Rework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn Settings' single long scroll into a list of seven categories, each with its own page and route.

**Architecture:** An enum `SettingsCategory` holds each category's slug, title, line, icon and section widgets. `SettingsPage({SettingsCategory? category})` renders the list (phone, no category), a category page (phone, with category), or a two-pane layout (wide). The router gets `/settings/:category` after `/settings/themes`.

**Tech Stack:** Flutter, go_router, Riverpod, flutter_test.

**Spec:** `docs/superpowers/specs/2026-11-14-settings-rework-design.md`

## Global Constraints

- Wide means `MediaQuery.sizeOf(context).width >= phoneBreakpoint` (720, `lib/ui/shell/adaptive_shell.dart`).
- Category order and slugs: library, playback, youtube, appearance, privacy, discord, about.
- Wide list pane is 280 px wide; plain `/settings` on wide shows Library.
- Unknown slug → Library.
- Section widgets and their keys are unchanged; `/settings/themes` keeps working.
- Run Flutter with `export PATH="$HOME/development/flutter/bin:$PATH"`; revert `dart format` changes to `test/ui/stats_page_test.dart` and `test/ui/ytm/artist_lookup_test.dart`.

## Review Focus

- `/settings/themes` must still open Themes, not be swallowed by `:category` (Task 2 router test).
- Phone Back from a category page returns to the list, including when the page was opened directly by `go` (Task 2: back falls back to `go('/settings')`).
- On wide, switching categories must not stack pages: Back/pop history doesn't grow (Task 2: uses `go`, test asserts `canPop` unchanged).
- Discord's section hides itself where unsupported; the Discord category must then be absent from the list too (Task 1).
- Signed-out Privacy still renders its signed-out note under the Privacy category (covered by existing privacy tests; pumped via section).

---

### Task 1: Categories

**Files:**
- Create: `lib/ui/settings/settings_categories.dart`
- Modify: `lib/ui/settings/settings_page.dart` (make `_FoldersSection`, `_AppearanceSection`, `_StorageSection`, `_LogsSection`, `_AboutSection` public: `FoldersSection`, `AppearanceSection`, `StorageSection`, `LogsSection`, `AboutSection`)
- Test: `test/ui/settings/settings_categories_test.dart`

**Interfaces:**
- Produces:
  - `enum SettingsCategory { library, playback, youtube, appearance, privacy, discord, about }` with `String get slug` (= `name`), `String get title`, `String get line`, `IconData get icon`, `List<Widget> get sections`.
  - `SettingsCategory settingsCategoryFromSlug(String? slug)` → Library for null/unknown.
  - `List<SettingsCategory> visibleSettingsCategories(WidgetRef ref)` — all, minus `discord` when `ref.watch(discordSupportedProvider)` is false.

Sections per category: library [FoldersSection, StorageSection]; playback [PlaybackSettingsSection, DownloadsSettingsSection]; youtube [YouTubeSettingsSection]; appearance [AppearanceSection]; privacy [PrivacySettingsSection, CrashReportsSettingsSection]; discord [DiscordSettingsSection]; about [AboutSection, LogsSection].

Lines: Library "Music folders, storage"; Playback "Equalizer, downloads"; YouTube "Sign-in, yt-dlp, recommendations"; Appearance "Themes, animations"; Privacy "Sharing, crash reports"; Discord "Show what you're playing"; About "Version, updates, bug reports, log".

- [ ] **Step 1: Write the failing tests**: `settingsCategoryFromSlug('youtube') == youtube`, `(null)` and `('nope')` → library; slugs in order equal `['library','playback','youtube','appearance','privacy','discord','about']`; `visibleSettingsCategories` drops discord when `discordSupportedProvider` is overridden false.
- [ ] **Step 2: Run** `flutter test test/ui/settings/settings_categories_test.dart` — Expected: FAIL (file missing).
- [ ] **Step 3: Implement** the file and the renames.
- [ ] **Step 4: Run** the same — Expected: PASS.
- [ ] **Step 5: Commit** `feat(settings): settings categories (SON-23)`.

### Task 2: Pages, layout and routes

**Files:**
- Modify: `lib/ui/settings/settings_page.dart`, `lib/router.dart`
- Test: `test/ui/settings_test.dart` (new layout tests; existing tests pump the right category), `test/router_test.dart`, plus any other test failing because a key moved off `/settings` (`test/ui/bug_report/bug_report_form_test.dart`, `test/ui/youtube_settings_test.dart`, `test/ui/account/profile_page_test.dart`).

**Interfaces:**
- Consumes: Task 1.
- Produces: `SettingsPage({SettingsCategory? category})`; route `/settings/:category` building `SettingsPage(category: settingsCategoryFromSlug(slug))`, declared after `themes`.

Behaviour:
- Phone, `category == null`: header "Settings" (with the existing Back-arrow rule), then one `ListTile` per visible category, key `settings.category.<slug>`, icon, title, line as subtitle, chevron; tap → `context.push('/settings/<slug>')`.
- Phone, category set: header with Back arrow (`context.canPop() ? pop : go('/settings')`) and the category title, then its sections.
- Wide: `Row` of a 280 px list (same tiles, selected = current category or Library, no chevron; tap → `context.go('/settings/<slug>')`) and an `Expanded` pane: category title header, then sections. No Back arrow in the pane.

- [ ] **Step 1: Write the failing tests** in `settings_test.dart`:
  - phone (400×900): `/settings` shows all seven tiles and no `settings.addFolder`; tapping `settings.category.about` shows `settings.checkForUpdates`; Back returns to the list.
  - phone: opening `/settings/youtube` by `go` then Back lands on `/settings`.
  - wide (1000×900): `/settings` shows the tiles and `settings.addFolder` (Library); tapping About shows `settings.checkForUpdates`, path `/settings/about`, and `GoRouter.of(...).canPop()` is the same as before the tap.
  - `/settings/nope` shows Library.
  - router_test: `/settings/themes` still opens `ThemesPage`; `/settings/about` opens `SettingsPage`.
- [ ] **Step 2: Run** `flutter test test/ui/settings_test.dart test/router_test.dart` — Expected: new tests FAIL.
- [ ] **Step 3: Implement** the layout and the route; add the `:category` route to test routers that build `SettingsPage`, and point existing tests at their category (`pumpSettings(location: '/settings/<slug>')`).
- [ ] **Step 4: Run** the full suite `flutter test` — Expected: all pass except the known flaky stats timing tests.
- [ ] **Step 5: Commit** `feat(settings): category list and pages (SON-23)`.
