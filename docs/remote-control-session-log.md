# Remote control (roadmap 5, step 3) — session log

Spec: [remote control design](superpowers/specs/2026-11-06-remote-control-design.md). Plan: [remote control plan](superpowers/plans/2026-11-06-remote-control.md).
Branch: `remote-control`, in the worktree `.worktrees/remote-control` of the main checkout (git-ignored through `.git/info/exclude`). It starts from `origin/claude/great-mccarthy-39er0g` (the design commit `080674c`). Not pushed, not merged. The main checkout's uncommitted work (volume memory, theme edits) is untouched.

Flutter is at `/home/deno/flutter/bin` (the plan's `~/development/flutter` path is wrong on this machine). There is no `supabase` CLI here.

## Status (2026-11-07): all 8 tasks done, final review clean

The work ran with subagent-driven development: each task got an implementer, a task review, and a scoped re-review after each fix round. After the eight tasks there was one whole-branch review on the most capable model, then one fix wave and a scoped re-review, which came back with all findings addressed.

| Task | What | Commits |
|---|---|---|
| 1 | Protocol messages | `5c295c9` |
| 2 | Channel, fake hub, Realtime RLS migration | `1d83fe1`, `ff0eb5a` |
| 3 | Host, `tracksByIds`, checked edits in PlayerService | `9690a3c`, `6f81677` |
| 4 | Controller | `ce296d0`, `67655dd` |
| 5 | PlayerView, device name, providers, main.dart wiring | `2b8c858` |
| 6 | Player UI reads the view | `1e3c950` |
| 7 | Devices button, picker, strip, islands | `014f483`, `c2cd120` |
| 8 | Play on / Add to queue on, `sendTo`, docs | `708d712`, `9fbf47b` |
| Final fixes | Phone entry point, own-drop presence, windowed sends, 3 s sync cap, cloud-sync follower listen, send islands, docs | `ad204a3`..`262e3e7` |

Tests: the full `flutter test` passed (2,483) and `flutter analyze` is clean. `flutter build apk --release` succeeds (85.7 MB). `flutter build linux --release` fails on this machine because the webkit2gtk-4.0 dev package (needed by desktop_webview_window) isn't installed; that's an environment problem, not this branch.

**Still to do by hand:** the "Remote control" section of `docs/manual-test-checklist.md` on two real devices, including the RLS check and the public-access (`private: false`) check.

## Rulings (each with its cost if wrong)

- `selectRemote(PlayerService, RemoteController, RemotePresence)` is a plain function. Cost: a trivial signature change.
- The RLS check moved to the manual checklist, because there's no supabase CLI on this machine. Cost: a policy typo is found only on the real project.
- Checked edits (`playAtIf`/`removeAtIf`/`moveIf`) live inside PlayerService's lock. Cost: three extra methods.
- The controller's optimistic Previous mirrors the host's 3 s restart threshold. Cost: none.
- The run-on position is anchored on local arrival time, not `at_ms`. Cost: about 100 ms of lag in the shown position.
- `remoteEndedProvider` is a `Provider<Stream>`, so the island subscribes itself and re-subscribes on a controller change. Cost: a missed island.
- Islands appear only for "didn't answer" and "lost", not for sign-out, because the spec names no sign-out notice. Cost: one island to add.
- `sendTo` doesn't sync; callers sync first (capped at 3 s). Cost: moving one await.
- `remoteDevicesProvider` is kept alive through `remoteHostFollowerProvider`. Cost: one listen line.
- Phone entry point: a devices button in the Home header, and a mini player shown while linked even with no track. Cost: moving one icon.
- The `cloudSyncFollowerProvider` read-only bug (pre-existing) is fixed here with `container.listen`, because Play on of fresh songs depends on it. Cost: none.
- Long sends are split into windows: `playTracks` sends at most 2,000 ids, keeping up to 1,000 before the start song, with the rest in `addToEnd` parts. `addNext`/`addToEnd` are sent in parts of 2,000. Cost: a huge remote "Play all" can't go Previous past 1,000 songs before the start.
- New copy not in the spec: the "Playing on <device>" / "Added to queue on <device>" islands after a Play on send. Cost: easy to remove.

## Known minor items left (triaged "can wait" by the final review)

- Protocol:
  - `kRemoteQueueWindow` isn't enforced on decode.
  - Some reject cases are untested.
  - The protocol imports player_service for `RepeatMode`.
- Channel:
  - Stream controllers are never closed.
  - Stale-callback guards are untested (needs the manual check).
- Host:
  - Local seeks of 400 ms or less aren't sent.
  - A `playTracks` waiting on unknown ids holds later commands, including pause, for up to 5 s.
  - The 5 s heartbeat goes to all present devices, about 78 KB with a 2,000-id queue. This is a spec-level change for later.
  - `sourcePlaylistId` isn't on the wire, so "PLAYING FROM" doesn't show for a remote.
- Controller:
  - Unknown ids are looked up again on each state.
  - A presence rename doesn't update the strip until the next status change.
  - The winner among several presence entries for one device depends on iteration order.
- UI:
  - The repeat cycle and the unknown-source check are duplicated.
  - The picker's row logic is duplicated between sheet and popup.
  - The picker's device list is a snapshot taken at open.
  - The FavoriteStar still shows on "Unknown song".
  - The song menu's plain "Add to queue" stays local while viewing a remote.
  - An empty playlist still shows Play on entries (they do nothing).
  - On a phone, the devices button is reachable from Home only (and Now Playing / mini player while linked).
- Tests:
  - A few weak or non-discriminating tests (player-bar right-click negative, link-ended-under-picker).
  - The `themes_page_test` flake under full-suite load (pre-existing).
