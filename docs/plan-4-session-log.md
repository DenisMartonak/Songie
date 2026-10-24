# Songies Plan 4: session log (kept current after every task)

_Last updated: 2026-10-24, after Task 4._

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
| 5. Motion kit and page transitions | not started | |
| 6. Living Now Playing | not started | |
| 7. Living pages | not started | |
| 8. Living shell | not started | |
| 9. Theme list and editor | not started | |
| 10. Idle test, docs, builds | not started | |
| Final whole-branch review + one fix wave | not started | |

Tests at `54558cc`: 857 passing, `flutter analyze` clean.

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
- **Task 7** must not be starved by the "newest wins" palette queue (playlist header and Home glow ask for covers too). *If wrong:* one parameter.

## Smaller issues left for the final review

- Task 1: a duplicated query; a weaker v4 migration test; no fonts-table test beyond migration.
- Task 2: catch-all error mapping on import; file I/O inside the DB transaction; concurrent imports of one file aren't serialised; Outfit files still say "Outfit Thin" internally (cosmetic).
- Task 3: the palette stream closes before a pending result arrives; cover bytes are read on the UI thread; a few test-precision gaps.
- Task 4: the cover-palette provider isn't auto-disposed; the theme tint is 25 % vs the cover tint's 30 %; Default/Terminal's Now Playing gradient changed to a darkened accent (Task 6 rebuilds it); muted text isn't contrast-checked.
- Carried forward: Task 5 must make every motion token zero under reduced motion and honour the OS setting everywhere; Task 8 tints the player bar; Task 9 refreshes the font list after a font import.
- Device sync (Plan 6) must re-register a synced font when its file arrives.

## Your checks (phone/desktop), once Plan 4 is done

- The three built-in themes look as specified; Outfit and JetBrains Mono show real bold weights.
- Colours follow each new song within a second; fast skipping never flashes a skipped song's colours.
