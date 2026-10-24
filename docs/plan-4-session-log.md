# Songies Plan 4: session log (kept current after every task)

_Last updated: 2026-10-25, after Task 9._

**To resume in a new Claude session:**
> Continue Songies Plan 4 subagent-driven on branch `plan-4-alive-ui-themes`. Read docs/plan-4-session-log.md and the ledger it names. Don't push or merge.

**Where things are:**
- **Branch:** `plan-4-alive-ui-themes`, made from `plan-3-downloads-fixes` at `766750b`. Plan 3 is finished but not merged, so Plan 4 builds on it. Nothing is pushed or merged.
- **Plan:** [Plan 4: a living UI and the theme engine](superpowers/plans/2026-10-23-songies-plan-4-alive-ui-and-themes.md)
- **Ledger:** `.superpowers/sdd/2026-10-23-songies-plan-4-alive-ui-and-themes/progress.md` (git-ignored). A task with a `Task N: complete` line there is done; resume at the first task without one. A task whose last ledger line is a fix round is mid-loop.
- **Plan 3 workspace** (`.superpowers/sdd/2026-10-23-songies-plan-3-fixes-and-downloads/`) is kept because its `final-review.md` holds 8 "can wait" findings not yet copied into PROGRESS.md.

## Progress

| Task | State | Commits |
|---|---|---|
| 1. Themes data (schema v5, ThemeRepository) | done, reviewed | `227d62c`, `f258632` |
| 2. Fonts (Outfit, JetBrains Mono, import) | done, reviewed | `c9abd88`, `9de8cf2` |
| 3. Cover palette and contrast | done, reviewed | `ae77456`, `ba94ed5` |
| 4. ThemeService, animated colours | done, reviewed | `4c07b99`, `54558cc` |
| 5. Motion kit and page transitions | done, reviewed | `6ef2dd9`, `3d45fb7` |
| 6. Living Now Playing | done, reviewed | `7bcee50`, `bb00ceb`, `4bbc441` |
| 7. Living pages | done, reviewed | `6d8e776`, `e912745`, `e3d7b06` |
| 8. Living shell | done, reviewed | `bb0d546`, `55da22b` |
| 9. Theme list and editor | done, reviewed | `4babfce`, `9489d18` |
| 10. Idle test, docs, builds | not started | |
| Final whole-branch review + one fix wave | not started | |

Tests at `9489d18`: 1,032 passing, `flutter analyze` clean.


## Decisions made on your behalf (each with its cost if wrong)

- **Fresh install gets Album glow, decided once** and stored, so it doesn't flip to Default when you add your first song. Existing installs store Default. *If wrong:* an upgraded install with an empty library gets Album glow.
- **Editing a built-in saves "<name> copy"**; theme names are unique ignoring case, and also against built-in names ("Default" → "Default 2"). *If wrong:* one condition.
- **Album glow's glow strength is 0.65** (the spec's example); Default and Terminal 0.4. *If wrong:* one number.
- **Fonts:** Google Fonts only publishes Outfit and JetBrains Mono as variable fonts, which Flutter won't weight correctly, so static 400/600/700/800 files were cut from the official ones with fontTools (allowed: no Reserved Font Name). *If wrong:* swapping font files.
- **An imported font named like a bundled one** becomes "<family> 2". *If wrong:* a suffixed name.
- **Colour picker:** Songies' own HSV picker with a hex field, not `flutter_colorpicker`. *If wrong:* more UI code.
- **`material_color_utilities`** is a direct dependency. *If wrong:* nothing.
- **Fast skipping:** only the newest pending cover is analysed; skipped-past songs are never analysed or shown. *If wrong:* a skipped song's colours are computed later on demand.
- **Accent contrast** pivots at the contrast-neutral luminance (0.179). *If wrong:* nothing visible.
- **Motion tokens** are created in Task 4 (the theme needs them), and Task 5 extends them. *If wrong:* nothing.
- **Existing `glow`/`miniPlayer` colours** serve as the plan's glow and tint. *If wrong:* a rename.
- **Shimmer skeletons** may animate while loading, but stop in the background. *If wrong:* nothing.
- **The active theme loads before the first frame**, so the app never flashes Default at start; if that read fails or takes over 2 s, it starts on Default. *If wrong:* a few ms of startup.
- **`animations` 3.0.0** (the current release) instead of the plan's 2.x. *If wrong:* nothing; same API.
- **Rows scrolling into view for the first time** also play their small entrance animation (a side of making late-loading lists animate). *If wrong:* skip it while scrolling.
- **Now Playing swipe-down works on desktop too**, and Default/Terminal keep their pre-Plan-4 Now Playing gradient. *If wrong:* one platform check.
- **The time label shows remaining time** (`-m:ss`), per the plan. *If wrong:* one label.
- **A swipe-close doesn't fly the cover** back to the mini player (Flutter skips that on gestures); the close button still does. *If wrong:* nothing practical.
- **Sidebar selection bar** slides between rows within a section and just appears when you jump to another section. *If wrong:* one overlay widget.
- **Only one sidebar row shows the selection bar**: on a playlist page that's the playlist, not the Library header too. *If wrong:* nothing.
- **Shell values the plan left open:** swipe-to-skip at 64 px or a 400 px/s fling, a 3 px selection bar, and a slider thumb that grows to 6 px on hover. *If wrong:* numbers.
- **The title bar is unchanged** (the plan gives it no new behaviour). *If wrong:* nothing.
- **Muted text is worked out, not stored** (spec §9's file shape wins over Plan 1's code), so exported themes match the spec and §9-shaped files import. Default's muted grey is unchanged; Terminal's moves from #a7a7a7 to #a0a0a0. *If wrong:* a formula.
- **Imported theme files are saved but not switched to.** *If wrong:* one call.
- **A font error inside a theme file** shows the font's own message ("That file isn't a font"); other problems say "That isn't a Songies theme file". Nothing is half-saved. *If wrong:* copy.
- **Light themes get light-style Material widgets** (dialogs, switches, sliders). *If wrong:* nothing.
- **Page palettes don't wait behind the song's:** the playlist header and Home glow ask for their cover colours through a path the "newest wins" queue can't cancel. *If wrong:* one parameter.
- **Playlist page Play button floats** and pins to the top bar, as the plan asks, so Play left its old row and Back moved into the bar. That's the one exception to "nothing moves". *If wrong:* restoring the old row order.
- **The playlist header colour** is blended toward the background until its text reaches 4.5:1. *If wrong:* less cover colour on pale covers.
- **Import skeletons** only show for the moment before a freshly imported playlist's songs load (imports save everything at once). *If wrong:* a longer-lived pending state.

## Smaller issues left for the final review

- Task 1: a duplicated query; a weaker v4 migration test; no fonts-table test beyond migration.
- Task 2: catch-all error mapping on import; file I/O inside the DB transaction; concurrent imports of one file aren't serialised; Outfit files still say "Outfit Thin" internally (cosmetic).
- Task 3: the palette stream closes before a pending result arrives; cover bytes are read on the UI thread; a few test-precision gaps.
- Task 4: the cover-palette provider isn't auto-disposed; the theme tint is 25 % vs the cover tint's 30 %; Default/Terminal's Now Playing gradient changed to a darkened accent (Task 6 rebuilds it); muted text isn't contrast-checked.
- Carried forward: Task 5 must make every motion token zero under reduced motion and honour the OS setting everywhere; Task 8 tints the player bar; Task 9 refreshes the font list after a font import.
- Task 5: transition durations are fixed when a page is built; router transitions under the setting aren't tested end-to-end; a few test-strength gaps.
- Task 6: skip direction is worked out inside build; the queue's lift animation and ripples ignore reduced motion; queue tests only run with animations off.
- Task 7: the playlist header always rebuilds; some tests end with playback running; `playlist_page.dart` is ~1,165 lines (the header belongs in its own file); no end-to-end import-skeleton test; queued palette requests can't be cancelled.
- Task 8: the nav bounce uses plain ease curves; the volume slider shows no thumb on a touch drag and sliders have no focus cue; the title transition is rebuilt every drag frame; dragged mini-player content slides under the play button; state is changed inside build; the reduced-motion test was never seen failing.
- Task 9: a font rollback after a failed theme save isn't guarded against a second database error; leaving the Themes page mid-import can throw; the base-colour table lives in a UI file; the colour square has no screen-reader value.
- Device sync (Plan 6) must re-register a synced font when its file arrives.

## Your checks (phone/desktop), once Plan 4 is done

- The three built-in themes look as specified; Outfit and JetBrains Mono show real bold weights.
- Now Playing: dragging it down shows the app underneath; rotate the phone mid-drag and press back mid-drag, and nothing freezes; the blur stays smooth while dragging (performance overlay).
- Playlist page: readable header over a pale cover; long titles fit with Android's Large font; nothing sits under a side notch in landscape.
- Shell: swipe the mini player to skip; the bottom-nav icon bounces; the desktop scrubber and volume thicken on hover; sidebar hover works on a light theme.
- Themes: make, edit, export and import a theme, including one with an imported font; a light theme looks right in dialogs and switches.
- Colours follow each new song within a second; fast skipping never flashes a skipped song's colours.
