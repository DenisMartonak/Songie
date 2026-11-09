# Listen together (SON-5, accounts step 4) — session log

Spec: [listen together design](superpowers/specs/2026-11-08-listen-together-design.md). Plan: [listen together plan](superpowers/plans/2026-11-09-listen-together.md). Linear: SON-5 (both documents are attached there too; the repo copies are the ones the build follows).
Branch: `listen-together`, in the main checkout, from `main` at `43a3a2b`. Not pushed, not merged. It does not contain the cover fixes (branch `cover-fixes`, SON-19/SON-20, pushed, waiting for the user's device check).

Flutter is at `$HOME/development/flutter/bin`.

## Status (2026-11-09): all 7 tasks built and reviewed; final review fixes in; waiting on the user's merge decision

Commits after the first pause: Task 4 `f774c98`, `984f19c`; Task 5 `c52f93b`; Task 6 `e9c2a0e`; Task 7 `78eaa98`, `6a15d6e`, `3309c56`; final-review fixes `206ac9f`, `fdbe57d`, `1bd1a02`. `flutter analyze` clean; full suite +2633 −2 (the two stats "under 500 ms" tests, which pass alone); APK debug and Linux builds succeed.

Open after the final fix wave (no second wave by process; the user decides):
- Important: a listener or queue guest paused by an unplugged headset or a call ("local hold") can't resume from inside the app — the play buttons stay disabled for non-full roles although `RoomGuestView.play()` rejoins. Only system media controls/keys work, and the Android notification goes after 10 idle minutes.
- Minor: a hold during a song load can be overridden by the guest's own play; the guest's own music plays (room routing already on) for up to 15 s before the host shows; a call starting while the host is paused takes no hold; a crashed host's old link still waits 15 s before "This room has ended".

Still to do by hand (the user): apply `supabase/migrations/20261109120000_listen_together.sql` (edited since the first pause: same-account leave) and run the checks in docs/supabase.md (now including the same-account leave step); the `xdg-open` link check; the manual checklist in docs/manual-test-checklist.md on two accounts.

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

## Rulings made after the first pause

6. When the host's queue changes but the current song is the same, the guest swaps its queue in place instead of restarting the song (spec: "a seek, not by cutting or restarting the song"; the plan said reload). Adds `PlayerService.replaceQueueAroundCurrent`. Cost: a little extra player code.
7. A guest's player tries only the host's current song and never skips ahead (new `PlayerService.skipUnplayable` flag, default on, turned off while guesting and restored on leaving), so a failing song stays silent. Cost: an extra player flag.
8. The real Supabase room backend and channel are the providers' lazy defaults instead of `main.dart` overrides (the plan's way broke 30 tests). Nothing touches Supabase until a room is used. Cost: two lines to move.
9. The manual `xdg-open songies://room/ABCD2345` check (Task 6 step 5) is left to the user: it registers the link handler in the desktop session. Cost: one manual check.
10. A guest knows every person's role (the guest panel shows them), via an additive getter on `RoomGuest`. Cost: a small getter.

Also from Task 6: the Linux runner is now single-instance (a second launch raises the open window). Windows link code is unbuilt (can't build on Linux).

11. While guesting, every local playback input (shortcuts, media session, SMTC, song taps, Start radio) goes through the room, so the role decides. Cost: a listener can't pause from the notification (Leave is the way out).
12. The room button is also in the phone Home header. Cost: one button.
13. The final fix wave covered the four Important findings, the `playSongs` cap and cheap minors. Cost: other minors ship.
14. The light heartbeat (songs only when the window changes) is a follow-up, not this branch. Cost: big-queue rooms use more Realtime bandwidth.
15. The account-switch order (leave/end sent under the new session) stays. Cost: a stale room row until the 24 h limit; it reads "This room has ended".

## Deferred minors, Tasks 4–6

Task 4: Ruling 1 clamping and "newer state replaces pending" untested; while waiting on an unplayable host song before any load, the guest shows its own queue and the view's playAt/remove/move do nothing; after a full reload a paused host's guest plays briefly then pauses; expected position not bounded by duration; a failed song is not retried within one queue epoch; a state during `join` leaves the hello timer running until the next state; stream controllers never closed; tests silence `debugPrint`; the guest's shuffle is forced off and repeat mirrored, kept after leaving; `_checkStarted` would misfire if playback ever reported "playing" late.

Task 5: tests written after the code (no RED run); provider wiring untested; no service-level test for the host vanishing (`hostGone`); remote-host test uses `pause` where the brief said `play`; leaving while `join` waits for the host relies on microtask order; leave/end during `open`'s backend call are no-ops; remote presence republished on every room status change; `dispose` leaves a guest's membership row; sign-in notice on `open` untested.

Task 6: the Linux link registration writes its file before `xdg-mime`, so a failed `xdg-mime` is never retried; `%`/`"` in an AppImage path not escaped; the link stream has no `onError`; packaging test doesn't check `local_command_line`; import order in `main.dart`.

## Build environment note

`flutter build linux` needs libcurl headers this machine lacks. The Task 6 implementer pointed the git-ignored `build/linux` CMake cache at headers extracted into a temporary session folder, which will be gone after a reboot. Lasting fix: `sudo dnf install libcurl-devel`.

Still to do by hand (the user), in addition to the migration: the `xdg-open` link check (Ruling 9).
