# Listen together (SON-5, accounts step 4) — session log

Spec: [listen together design](superpowers/specs/2026-11-08-listen-together-design.md). Plan: [listen together plan](superpowers/plans/2026-11-09-listen-together.md). Linear: SON-5 (both documents are attached there too; the repo copies are the ones the build follows).
Branch: `listen-together`, in the main checkout, from `main` at `43a3a2b`. Not pushed, not merged. It does not contain the cover fixes (branch `cover-fixes`, SON-19/SON-20, pushed, waiting for the user's device check).

Flutter is at `$HOME/development/flutter/bin`.

## Status (2026-11-09): paused by the user after Task 3 of 7

The work runs with subagent-driven development: each task gets an implementer, a task review, and a scoped re-review after each fix round. The ledger (git-ignored) is `.superpowers/sdd/2026-11-09-listen-together/progress.md`; it holds the pre-flight scan, every ruling and every deferred minor. If it is gone, this log and `git log` are the record.

| Task | What | Commits | Review |
|---|---|---|---|
| 1 | Supabase tables, functions and Realtime rules; `RoomBackend` | `a9425fe`, fix `f7f6be8` | clean after 1 fix round |
| 2 | Room messages, `RoomSong`, codes and links | `e4e4069` | approved |
| 3 | `RoomChannel`, `FakeRoomHub`, `RoomHost` | `250c512` | approved |
| 4 | The guest follows (`RoomGuest`, `RoomGuestView`) | — | not started |
| 5 | `RoomService`, providers, remote-control changes | — | not started |
| 6 | Links open the app (app_links, Android/Windows/Linux) | — | not started |
| 7 | Room UI | — | not started |

Tests: after Task 3, `flutter analyze` is clean and the full suite fails only on the two known stats "under 500 ms" timing tests (they pass on their own).

**To resume:** start at Task 4 with `superpowers:subagent-driven-development` on the plan; tasks with a `complete` line in the ledger are done. Carry Ruling 1 (below) and the Task 2 minor about clamping state on the guest into Task 4's dispatch.

**Still to do by hand (the user):** apply `supabase/migrations/20261109120000_listen_together.sql` to the Supabase project and run the checks in the "Listen together" section of `docs/supabase.md`. The SQL has never run against a database.

## Rulings (each with its cost if wrong)

1. Guests' `playAt`/`remove`/`move` requests carry `args.videoId` of the song they saw at that index plus the state's epoch; the host passes its own track id to `playAtIf`/`removeAtIf`/`moveIf` only when the video id matches, else sends fresh state (the plan's guard needs a track id a guest can't know). Cost: a stale jump could hit a neighbouring copy of the same song.
2. Leave-reason islands: ended or host gone → "The room ended"; removed → "You were removed from the room"; unreachable → "Couldn't reach the room"; outdated → "Update Songies to join this room". Cost: copy only.
3. `roomInviteProvider` is a `NotifierProvider<RoomInvite, String?>`, not a `StateProvider` (Riverpod 3 keeps that only in its legacy import). Cost: a rename.
4. The migration is written and documented but not applied; applying it is the user's step. Cost: one SQL file to run.
5. **Security, accepted for rooms among friends:** Supabase Realtime checks its rules when a client joins the channel, not per message, and broadcasts carry no verified sender. So the server only keeps non-members out; any member could pose as the host or another guest, and removing someone or ending the room cuts off an already-connected client only when it reconnects or refreshes its token. The per-event "host only" rule was dropped. Cost: a friend could disrupt a room; enforcing it would need a server-relayed design.

## Deferred minors (for the final whole-branch review to triage)

Task 1: helper comment says "not callable by apps" though granted to `authenticated`; concurrent `open_room` by one host can leave two open rooms; a removed guest can rejoin at once (no ban); `open_room` empty result unguarded; no tests for timeout/client errors → offline or unknown → other; SQL cap 10 not tied to `kRoomMaxPeople`; `gen_random_bytes(16)` called per row; `is_room_host` now unused by any policy.

Task 2: link tests lack out-of-alphabet, wrong-path and `http://` cases; `RoomSong` accepts an empty `videoId`; state decoding doesn't bound the song list or reject negative numbers (the guest should clamp); `roomSongOf` never sets `artUrl`; `repeat`'s wire value is the enum name; `tracksForSongs` is sequential.

Task 3: a connection blip makes the channel report nobody present, so the host sees a burst of left/joined events; the request chain has no `catchError`; the 250 ms "debounce" is a throttle; no guard against removing or re-roling the host's own device; `setRole` sends after `stop`; a doc comment claims channel tests that don't exist; tests miss timers-after-stop, an exact heartbeat count, `GuestLeft`, the `playAt`/`move` guards and `addNext`.
