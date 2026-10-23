# Songies Plan 4: A Living UI and the Theme Engine — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Songies feel alive instead of flat. Colours follow the playing song's cover, and the app gets motion, depth and feedback throughout. It also gets the spec's full theme engine: saved, synced themes with an editor, three built-ins, and bundled plus imported fonts.

**Architecture:**
- **Theme layer:** a `ThemeService` turns the active `ThemeSpec` into `SongiesColors`. When `followCover` is on, it mixes in a `CoverPalette` taken from the current track's artwork. Palette changes animate through `SongiesColors.lerp`, so the whole app eases into the new song's colours.
- **Motion layer:** a small shared kit (`lib/ui/motion/`) holds one set of duration and curve tokens and a few reusable widgets: press feedback, staggered entrance, skeleton shimmer and equalizer bars. Pages adopt it instead of hand-rolling animations.
- **Battery and CPU:**
  - Nothing animates while the app is idle. Looping animations run only while a song is playing and the widget is visible.
  - The OS "reduce motion" setting, or our own **Reduce animations** setting, turns motion into instant changes.

**Tech Stack:** Flutter 3.47 / Dart 3.13, drift (schema **v5**), Riverpod, go_router, `material_color_utilities` (already a Flutter dependency) for colour extraction, `animations` 2.x for page transitions, `flutter_colorpicker` (or a built-in HSV picker if it isn't maintained at plan time).

**Spec:** `docs/superpowers/specs/2026-10-21-songies-design.md`, §9 (themes, the full theme spec, built-ins, fonts, follow cover, editor) and §11 (header glow, mini-player tint, the Now Playing blurred cover with swipe-down, skeleton loaders, empty states). This plan comes after Plan 3 (`docs/superpowers/plans/2026-10-23-songies-plan-3-fixes-and-downloads.md`).

## Decisions this plan makes beyond the spec

- **D1:** the user asked for the UI to feel "alive" ("this looks too soulless"). The spec's §11 layout stays exactly as it is. This plan adds motion and colour on top of it, and does not move anything.
- **D2:** `palette_generator` is discontinued. Colours come from `material_color_utilities`, using `QuantizerCelebi` on a 64×64 downscale and then `Score`. It runs in an isolate, once per art ref, and the result is cached in memory and as `<appData>/art/<ref>.palette.json`.
- **D3:** **"Album glow" becomes the default theme on fresh installs**, because it's the livelier built-in. Existing installs keep whatever is active (Default unless changed).
- **D4:** lyrics (originally bundled with themes) become their own plan, Plan 5. Device sync moves to Plan 6 and packaging to Plan 7.
- **D5:** a **Reduce animations** switch in Settings → Appearance (device-local `reduce_motion`, default off). It's also forced on when `MediaQuery.disableAnimations` is true.

## Global Constraints

- The spec §9 theme JSON shape is verbatim, with the keys `base, background, surface, text, accent, followCover, glowStrength, cornerRadius, fontFamily, fontFileHash, fontScale, blurNowPlaying`. `mutedText` stays derived, as in Plan 1's `ThemeSpec`, and is not stored.
- **Built-ins (read-only; editing one creates a copy):**

  | Theme | Base | Accent | Font | Radius | Follow cover |
  |---|---|---|---|---|---|
  | **Default** | charcoal | `#1db954` | Inter | 6 | off |
  | **Album glow** | charcoal | cover-derived (`#1db954` fallback) | Outfit | 12 | on |
  | **Terminal** | black | `#00e5ff` | JetBrains Mono | 0 | off |

- Bundled fonts are Inter, Outfit and JetBrains Mono (OFL; add their `OFL.txt`).
- Imported fonts are `.ttf`/`.otf` files copied to `<appData>/fonts/<sha256>.<ext>` and registered at startup with `FontLoader`.
- New synced tables: `themes(name, spec_json)` and `fonts(family, file_hash, ext)`, with sync columns. `schemaVersion` becomes **5**.
- The active theme id lives in device-local `settings` (`active_theme_id`). The theme list syncs.
- **Contrast:** text on the background and on the accent must reach WCAG AA (4.5:1). If it doesn't, the text falls back to white or black, whichever passes.
- **Motion tokens** (`lib/ui/motion/motion.dart`), used everywhere and never as ad-hoc durations:

  | Token | Duration | Curve | Used for |
  |---|---|---|---|
  | `Motion.quick` | 120 ms | — | presses |
  | `Motion.standard` | 250 ms | `Curves.easeOutCubic` | most transitions |
  | `Motion.emphasized` | 450 ms | `Curves.easeInOutCubicEmphasized` | page/track changes |
  | `Motion.colour` | 600 ms | — | palette transitions |

  With reduced motion, every token is `Duration.zero`.
- **No idle animation:** an always-running `AnimationController` is allowed only while `PlayerState.playing` is true and the widget is in a visible route. A test asserts that no frames are scheduled once playback is paused and on-screen animations have settled.
- Tests never touch the network. Palette tests use small generated images.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **A cover with no clear colour** (greyscale, black, white, or the gradient placeholder): the palette falls back to the theme accent, and text stays readable (AA). Pinned in Task 3.
2. **Rapid skipping through songs:** palette extraction for skipped songs is cancelled or ignored, colours never flash the colours of a song that was skipped past, and isolates don't pile up. Pinned in Task 3.
3. **Battery:**
   - Paused playback, Now Playing left open: no frames are scheduled.
   - Equalizer bars and glow animations stop when the app is backgrounded (`AppLifecycleState.paused`).
   - Pinned in Tasks 5 and 6.
4. **An imported font file that is corrupt or not a font:** a clear message and nothing saved. A synced theme naming a font this device lacks falls back to Inter until the font arrives. Pinned in Task 2.
5. **Editing the active theme:** the live preview never writes until Save. Cancel restores the previous look. Editing a built-in silently creates "<name> copy". Pinned in Task 9.

---

## File Structure

```
lib/data/tables.dart, database.dart          v5: themes, fonts (Task 1)
lib/theme/theme_repository.dart              built-ins + CRUD + active id (Task 1)
lib/theme/font_service.dart                  bundled/imported fonts, FontLoader (Task 2)
lib/theme/cover_palette.dart                 CoverPalette extraction + cache (Task 3)
lib/theme/contrast.dart                      WCAG contrast + fallback (Task 3)
lib/theme/theme_service.dart                 spec + palette → animated SongiesColors (Task 4)
lib/theme/app_theme.dart                     SongiesColors.lerp, glow/tint fields (Task 4)
lib/ui/motion/{motion,pressable,fade_slide_in,shimmer,equalizer_bars,animated_tint}.dart  (Task 5)
lib/router.dart                              shared-axis/fade-through transitions (Task 5)
lib/ui/now_playing/*                         living Now Playing (Task 6)
lib/ui/home, library, playlist, search       living pages (Task 7)
lib/ui/shell/{mini_player,player_bar,bottom_nav,sidebar}.dart   living shell (Task 8)
lib/ui/settings/themes/*                     theme list + editor + import/export (Task 9)
```

---

### Task 1: Themes data — schema v5 and `ThemeRepository`

**Files:**
- Modify: `lib/data/tables.dart`, `lib/data/database.dart`, `lib/theme/theme_spec.dart` (add the `albumGlow` and `terminal` built-ins)
- Create: `lib/theme/theme_repository.dart`
- Test: `test/data/migration_test.dart`, `test/theme/theme_repository_test.dart`

**Interfaces:**
- Produces:
  - `ThemeEntry { String id; String name; ThemeSpec spec; bool builtIn }`. Built-ins have the fixed ids `builtin:default`, `builtin:album-glow` and `builtin:terminal`, and are never stored in the db.
  - `ThemeRepository(AppDatabase db, SyncStamp stamp, SettingsRepository settings)`:
    - `Stream<List<ThemeEntry>> watchAll()`: built-ins first, then saved themes by name.
    - `Stream<ThemeEntry> watchActive()`: falls back to `builtin:album-glow` for a fresh install (no settings row and no tracks) and to `builtin:default` otherwise (D3). It also falls back to `builtin:default` if the stored id is missing or tombstoned.
    - `Future<Result<String>> save(String? id, String name, ThemeSpec spec)`: a built-in id or null inserts a new row. The name is trimmed, 1–40 characters, and unique among non-deleted themes; a clash gets " 2", " 3" and so on.
    - `Future<Result<void>> delete(String id)`: a tombstone. Built-ins → `invalidInput`. Deleting the active theme switches to Default.
    - `Future<void> setActive(String id)`.
    - `Future<Result<String>> duplicate(String id)`: names it "<name> copy".

- [ ] **Step 1: Write failing tests:**
  - Migration v4 → v5.
  - The three built-ins have exactly the §9 values from Global Constraints.
  - Save, rename and delete are stamped.
  - A name clash produces "Mine 2".
  - Deleting a built-in is refused.
  - Deleting the active theme switches to Default.
  - A fresh install is active on Album glow; an existing library is active on Default.
  - `spec_json` round-trips through `ThemeSpec.fromJson`/`toJson`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement**, then run `build_runner`.
- [ ] **Step 4: Run** `flutter test test/data test/theme`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: schema v5 themes and fonts, theme repository with built-ins`.

### Task 2: Fonts — bundled Outfit and JetBrains Mono, import `.ttf`/`.otf`

**Files:**
- Create: `lib/theme/font_service.dart`, `assets/fonts/Outfit-*.ttf`, `assets/fonts/JetBrainsMono-*.ttf` (400/600/700/800 where available), plus their OFL texts
- Modify: `pubspec.yaml`, `lib/main.dart`
- Test: `test/theme/font_service_test.dart`

**Interfaces:**
- Produces:
  - `FontService(AppDatabase db, SyncStamp stamp, Directory fontsDir, {FontRegistrar register})`.
  - `typedef FontRegistrar = Future<void> Function(String family, List<Uint8List> data)`. The default uses `FontLoader`.
  - `Future<void> loadImported()`: registers every stored font at startup, and logs and skips a file that's missing.
  - `Future<Result<String>> import(String path)`:
    - Checks the first 4 bytes: `00 01 00 00`, `true` or `OTTO`.
    - Rejects anything over 10 MB.
    - Copies the file to `<sha256>.<ext>`.
    - The family name is the file's base name, with `-Regular`, `-Bold` and similar suffixes stripped.
    - Inserts a stamped `fonts` row (deduped by hash), registers the font and returns the family.
  - `List<String> bundledFamilies = ['Inter', 'Outfit', 'JetBrains Mono']`.
  - `Stream<List<FontEntry>> watchAll()`.
  - `String resolveFamily(ThemeSpec s)`: a missing imported family → `'Inter'`.

- [ ] **Step 1: Write failing tests:**
  - Importing a valid fixture font → a row, a file and a register call.
  - The same file again → the same family and no second row.
  - A `.txt` renamed to `.ttf` → `Err(invalidInput, "That file isn't a font")`.
  - An 11 MB file → `Err(invalidInput, "Font files must be under 10 MB")`.
  - `resolveFamily` on an unknown family → Inter.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement**, and add the font assets to `pubspec.yaml`.
- [ ] **Step 4: Run** the tests. Expected: PASS.
- [ ] **Step 5: Commit** `feat: bundled Outfit and JetBrains Mono, font import`.

### Task 3: Cover palette and contrast

**Files:**
- Create: `lib/theme/cover_palette.dart`, `lib/theme/contrast.dart`
- Test: `test/theme/cover_palette_test.dart`, `test/theme/contrast_test.dart`

**Interfaces:**
- Produces:
  - `CoverPalette { Color dominant; Color vibrant; Color muted; bool isFallback }`, with `toJson`/`fromJson`.
  - `CoverPaletteService(ArtCache art, {Future<CoverPalette?> Function(Uint8List) extract})`:
    - `Future<CoverPalette?> paletteFor(String? artRef)` checks memory first, then `<ref>.palette.json`, then extracts in an isolate.
    - There is at most one extraction in flight. A newer request supersedes older ones: the older futures complete with the result for their own ref but are never applied by `ThemeService` once stale.
  - The extractor:
    - Downscales to 64×64 and runs `QuantizerCelebi.quantize(pixels, 64)` and then `Score.score`.
    - `vibrant` = the top score.
    - `dominant` = the most populous colour.
    - `muted` = `dominant` at 40 % chroma.
    - If the top score has chroma < 15 (greyscale art) → `isFallback = true`.
  - `double contrastRatio(Color a, Color b)`.
  - `Color readableOn(Color bg, {Color preferred})` returns `preferred` if it reaches ≥ 4.5:1, otherwise white or black, whichever is higher.
  - `Color ensureAccentContrast(Color accent, Color bg)` lightens or darkens the accent in HCT tone until it reaches ≥ 3:1 against the background.

- [ ] **Step 1: Write failing tests:**
  - A generated image that's 70 % `#d03030` and 30 % `#202020` → `vibrant` is close to `#d03030` (ΔE small), with `isFallback` false.
  - A pure grey image → `isFallback` true.
  - The cache: a second call doesn't run the extractor; after a restart (new service, same dir) the result is read from JSON.
  - Supersede: requests for refs A then B with A's extractor slow → the provider stream emits only B.
  - Contrast: white on `#121212` passes; `#1db954` text on `#ffffff` falls back to black; `ensureAccentContrast(#202020, #121212)` returns a colour with a ratio of at least 3.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the tests. Expected: PASS.
- [ ] **Step 5: Commit** `feat: cover palette extraction with cache and contrast checks`.

### Task 4: `ThemeService` — animated colours across the app

**Files:**
- Create: `lib/theme/theme_service.dart`
- Modify: `lib/theme/app_theme.dart`, `lib/app.dart`, `lib/providers.dart`
- Test: `test/theme/theme_service_test.dart`, `test/theme/app_theme_test.dart`

**Interfaces:**
- `SongiesColors` gains:
  - `glowColor`: the header glow colour.
  - `tint`: the mini-player and player-bar tint.
  - `nowPlayingTop` and `nowPlayingBottom`: the Now Playing gradient.
  - `fontFamily`.
  - A real `lerp` that interpolates every colour and `radius`. `fontFamily` and `blurNowPlaying` switch at t = 0.5.
- Produces:
  - `songiesColorsProvider`: a `Provider<SongiesColors>` driven by the active theme and, when `followCover` is on, the current track's `CoverPalette`. With follow cover:
    - accent = `ensureAccentContrast(vibrant, background)`
    - glow = vibrant at `glowStrength`
    - tint = `Color.alphaBlend(vibrant @ 30 %, surface)`
    - Now Playing gradient = `dominant` darkened 55 % → background
    - Without a palette, or when `isFallback`, the theme's own accent is used.
  - `SongiesApp` wraps `MaterialApp.router` in `AnimatedTheme(duration: Motion.colour)` built from that, so every widget animates its colours together and nothing animates on its own.
  - `fontScale` → `MediaQuery.textScaler` multiplied by `fontScale`.

- [ ] **Step 1: Write failing tests:**
  - `lerp` at 0, 0.5 and 1.
  - Follow cover on with a red palette → accent, glow and tint come from red.
  - Follow cover off → the theme accent.
  - An `isFallback` palette → the theme accent.
  - Changing track → the colours tween over 600 ms (pump halfway, and the colour lies between the two).
  - Reduced motion → an instant change.
  - `fontScale` 1.2 → a text scale of 1.2×.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test`. Expected: PASS, with existing UI tests still green.
- [ ] **Step 5: Commit** `feat: theme service, cover-following colours with animated transitions`.

### Task 5: The motion kit and page transitions

**Files:**
- Create in `lib/ui/motion/`: `motion.dart`, `pressable.dart`, `fade_slide_in.dart`, `shimmer.dart`, `equalizer_bars.dart`, `visible_ticker.dart`
- Modify: `lib/router.dart`, `lib/ui/settings/settings_page.dart` (the Appearance section with **Reduce animations**)
- Test: `test/ui/motion/*_test.dart`, `test/router_test.dart`

**Interfaces:**
- Produces:
  - `Motion` tokens (Global Constraints), and `Motion.of(context)` returning the tokens, or zero durations when motion is reduced.
  - `reduceMotionProvider` (setting OR `MediaQuery.disableAnimations`).
  - `Pressable({required Widget child, VoidCallback? onTap, VoidCallback? onLongPress, double pressedScale = 0.97})`: scales down over `Motion.quick` while pressed, keeps the ink ripple, and adds a hover lift on desktop (the surface lightens 4 %).
  - `FadeSlideIn({required int index, required Widget child})`: fades in and slides up 12 px, staggered 30 ms per index and capped at index 8. It plays only the first time a page builds, never again on scroll-back.
  - `Shimmer({required Widget child})` and `SkeletonBox(width, height)`: a 1.2 s sweep while visible.
  - `EqualizerBars({required bool playing, double size = 14})`: three bars. They animate only while `playing` and visible (`VisibleTicker`, which mutes its ticker via `TickerMode` and `AppLifecycleState`). They are static bars when paused.
  - Router transitions:
    - Playlist pushes use a shared-axis horizontal transition (`animations` `SharedAxisTransition`).
    - Tab switches use a fade-through.
    - Now Playing slides up from the bottom with `Motion.emphasized` (it already has a custom page; tune it).

- [ ] **Step 1: Write failing tests:**
  - `Pressable` is at scale 0.97 mid-press and 1.0 after release.
  - `FadeSlideIn` index 3 starts after 90 ms, and with reduced motion it is visible at once.
  - `EqualizerBars` with `playing: false` → `tester.binding.hasScheduledFrame` is false after `pumpAndSettle`; with `playing: true` it is true.
  - App lifecycle `paused` stops the ticker.
  - The router: pushing a playlist uses a `SharedAxisTransition`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the tests. Expected: PASS.
- [ ] **Step 5: Commit** `feat: motion kit, reduced-motion setting and page transitions`.

### Task 6: A living Now Playing

**Files:**
- Modify: `lib/ui/now_playing/now_playing_page.dart`, `now_playing_header.dart`, `now_playing_controls.dart`, `now_playing_queue.dart`, `lib/ui/shell/mini_player.dart`, `lib/ui/shell/player_bar.dart`
- Test: `test/ui/now_playing/*_test.dart`

**Behaviour (exact):**
- **Background:**
  - When `blurNowPlaying` is on, the cover is blurred (σ 40, rendered once per track as a `RepaintBoundary` at low resolution) under the `nowPlayingTop → nowPlayingBottom` gradient.
  - When it's off, only the gradient shows.
- **Track change:**
  - The artwork crossfades and scales from 0.92 to 1 over `Motion.emphasized`.
  - The title and artist slide 16 px in the skip direction (left for next, right for previous) while fading.
- **Play/pause:**
  - The artwork eases to 1.0 while playing and 0.88 when paused (Spotify-like breathing room) over `Motion.standard`.
  - The play button is an `AnimatedIcon(AnimatedIcons.play_pause)` on an accent-filled circle that pulses once (1.0 → 1.06 → 1.0) when pressed.
- **Hero:** the mini-player / player-bar artwork flies to the Now Playing artwork (`Hero` tag `np-art`).
- **Swipe down to collapse** (spec §11):
  - Dragging moves the page.
  - Releasing past 25 % of its height, or flinging faster than 700 px/s, pops it. Otherwise it springs back.
- **Scrubber:**
  - The thumb grows from 0 to 12 px while dragging.
  - The elapsed and remaining labels update live.
  - The buffered part is drawn at 30 % opacity.
- **Long titles** scroll as a marquee only while playing and only if they overflow, pausing 2 s at each end.
- **Queue tab:** the current row shows `EqualizerBars`, and a reorder lifts the row with a shadow.
- **Downloaded icon** (from Plan 3): it stays as it is and fades in.

- [ ] **Step 1: Write failing widget tests:**
  - Paused → the artwork scale is 0.88; playing → 1.0.
  - The next track → the title `SlideTransition` offset is negative mid-animation.
  - A drag of 30 % of the height → the page is popped; a drag of 10 % → it springs back.
  - Blur off → no `ImageFiltered`/`BackdropFilter` in the tree.
  - Paused with motion settled → no scheduled frame.
  - Reduced motion → no transitions.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the tests. Expected: PASS.
- [ ] **Step 5: Commit** `feat: living Now Playing — cover glow, motion, swipe to collapse`.

### Task 7: Living pages — Home, Library, Playlist, Search

**Files:**
- Modify: `lib/ui/home/home_page.dart`, `lib/ui/library/library_page.dart`, `lib/ui/playlist/playlist_page.dart`, `lib/ui/search/search_page.dart`, `lib/ui/library/import_dialog.dart`
- Test: the matching widget tests

**Behaviour (exact):**
- **Home:**
  - The greeting depends on local time: **"Good morning"** 05–11, **"Good afternoon"** 12–17, **"Good evening"** 18–04.
  - A header glow: a radial gradient of `glowColor` behind the greeting, tinted by the last played track's palette even when nothing is playing.
  - Quick tiles and cards use `Pressable` and enter with `FadeSlideIn`.
  - A playing playlist's tile shows `EqualizerBars`.
- **Playlist:**
  - The hero background is a vertical gradient from the playlist cover's `dominant` colour to the background.
  - The hero collapses on scroll: the cover shrinks and fades, and the title moves into a pinned top bar that fades in past 60 % collapse.
  - The playing row shows `EqualizerBars` instead of its number, with its title in accent.
  - The Play button is a floating accent circle that pins to the top bar on scroll (Spotify-style).
  - Rows use `Pressable`.
  - The removed-on-YT and download states keep their Plan 2/3 visuals.
- **Library:** filter chips animate their selection (background and check, `Motion.standard`), and the list cross-fades when the filter changes.
- **Search:** results fade in, and the empty query shows "Search your library" with a gentle icon. No results shows **"Nothing matches '<q>'"**.
- **Skeletons** (spec §11): while an import runs, the new playlist page shows 8 `SkeletonBox` rows until the entries arrive. Home's first load, before the playlists stream emits, shows skeleton tiles.
- **Empty states** (spec §11):
  - Home with no playlists: an icon, **"Your music lives here"**, and the buttons **Import a YouTube playlist** and **Add music folder**.
  - An empty playlist: **"Add songs to get started"** with an **Add songs** button.

- [ ] **Step 1: Write failing widget tests:**
  - The greeting at 07:00, 13:00 and 23:00, using `nowProvider`.
  - The playing row shows `EqualizerBars`.
  - Scrolling the playlist by 300 px shows the pinned title.
  - Skeleton rows appear while entries are empty and an import is pending.
  - Both empty-state texts and buttons.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: living Home, Library, Playlist and Search pages`.

### Task 8: A living shell — mini player, player bar, nav, sidebar

**Files:**
- Modify: `lib/ui/shell/mini_player.dart`, `player_bar.dart`, `bottom_nav.dart`, `sidebar.dart`, `title_bar.dart`
- Test: the matching widget tests

**Behaviour (exact):**
- **Mini player:**
  - The fill is `tint`, animated by the theme.
  - The thin progress line is in accent.
  - Swiping left or right skips next or previous, with the content sliding.
  - A tap opens Now Playing with the hero.
  - A track change crossfades the art.
- **Bottom nav** (spec §11):
  - The active icon swaps filled/outline with a 1.0 → 1.12 → 1.0 bounce.
  - The label colour animates.
  - The gradient fade into the background stays.
- **Desktop player bar:**
  - The background is `surface` blended with `tint` at 40 %.
  - Hovering the scrubber thickens it from 4 to 6 px and shows its thumb.
  - The volume slider behaves the same way.
- **Sidebar:**
  - Rows have a hover highlight (`Motion.quick`).
  - The playing playlist shows `EqualizerBars`.
  - The selected row has an accent bar on its left edge that slides between selections.

- [ ] **Step 1: Write failing widget tests:**
  - A swipe on the mini player → `player.next()`.
  - The nav icon is scaled mid-animation after a tab tap.
  - Hovering the player-bar scrubber → height 6.
  - The sidebar's playing playlist row has `EqualizerBars`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the tests. Expected: PASS.
- [ ] **Step 5: Commit** `feat: living shell — tinted mini player, animated nav, hover states`.

### Task 9: Theme list and editor

**Files:**
- Create in `lib/ui/settings/themes/`: `themes_page.dart`, `theme_editor_page.dart`, `theme_preview.dart`, `colour_field.dart`, `theme_file.dart`
- Modify: `lib/router.dart` (`/settings/themes` and `/settings/themes/edit/:id`), `lib/ui/settings/settings_page.dart` (Appearance → Themes), `lib/ui/home/home_page.dart` (the header gear already reaches Settings)
- Test: `test/ui/settings/themes/*_test.dart`, `test/theme/theme_file_test.dart`

**Interfaces / behaviour:**
- **Themes page:**
  - A grid of cards, each a mini preview (background, surface, accent, a sample title in the theme font), with a check on the active one.
  - Tapping a card applies it with the `Motion.colour` transition.
  - The ⋯ menu offers Edit, Duplicate, Export and Delete (no Delete for built-ins).
  - The page actions are **New theme** and **Import**.
- **Editor**, with a live preview pane:
  - The controls:
    - **Base:** charcoal, black or light. Choosing one resets the colours to its defaults.
    - **Colour pickers:** background, surface, text and accent. Each offers 8 presets plus a custom HSV picker with a hex field.
    - **Follow cover** switch.
    - **Glow strength** slider, 0–1.
    - **Corner radius** slider, 0–24.
    - **Font:** bundled fonts, imported fonts, and **Import font…**, which calls `FontService.import`.
    - **Font scale** slider, 0.85–1.3.
    - **Blur Now Playing** switch.
    - **Name.**
  - The preview pane is a scaled-down Home tile row, a playlist row and a mini player, all rendered with the edited spec through a local `Theme`. The app's real theme doesn't change until **Save**.
  - **Save** → `ThemeRepository.save` and `setActive`. For a built-in, it saves as a new "<name> copy".
  - **Cancel**, or Back with changes, asks **"Discard changes?"**.
  - A contrast warning chip appears under the colour pickers when text on the background is below 4.5:1: **"Text may be hard to read"**.
- **Export:** a `.songies-theme.json` file, `{"songiesTheme": 1, "name": ..., "spec": {...}, "font": {"family", "ext", "base64"}?}`. The font is embedded only if it was imported. It's saved with the same save dialog as the log export.
- **Import:** pick the file and validate it. A bad file → **"That isn't a Songies theme file"**. If an embedded font is present, it's imported first. The theme is saved with a de-duplicated name.

- [ ] **Step 1: Write failing tests:**
  - `theme_file` round-trip, with and without a font.
  - A bad JSON file → `Err`.
  - Editor: moving the radius slider changes the preview's radius but not `songiesColorsProvider`. Save writes it; Cancel with changes shows the dialog.
  - Editing Default and saving → a new "Default copy" that becomes active.
  - The contrast chip shows for `#777777` text on `#888888`.
  - Delete is hidden for built-ins.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test` and `flutter analyze`. Expected: PASS, with no issues.
- [ ] **Step 5: Commit** `feat: theme list, live editor, import and export`.

### Task 10: Performance check, docs and builds

**Files:** `docs/PROGRESS.md`, `docs/manual-test-checklist.md`, `test/ui/idle_frames_test.dart`

- [ ] **Step 1: Idle test:**
  - Pump the full app shell with a paused track, on Home and then on Now Playing.
  - After `pumpAndSettle`, `tester.binding.hasScheduledFrame` must be false.
  - Then simulate `AppLifecycleState.paused` while playing, and expect no further frames to be scheduled.
- [ ] **Step 2:** Run `flutter test`, `flutter analyze`, `flutter build apk --release` and `flutter build linux --release`. Expected: all pass, with no issues and both builds made.
- [ ] **Step 3: Manual checklist additions:**
  - Colours follow each new song within a second, smoothly.
  - Skipping fast never shows a skipped song's colours.
  - Paused Now Playing for 5 minutes → the battery/CPU graph is flat (Android) / CPU use < 1 % (desktop task manager).
  - Reduce animations removes motion.
  - Importing a font works, and a non-font file is refused.
  - A theme exported on one device imports on another.
  - The three built-ins look as specified.
- [ ] **Step 4: PROGRESS.md:** record Plan 4 as done, with its rulings and parked items. Next is Plan 5 (lyrics), written from spec §10.
- [ ] **Step 5: Commit** `docs: Plan 4 verification, checklist and progress`.
