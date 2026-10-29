# Songies Plans 6–7: session log

_Last updated: 2026-10-29. **Plans 6 and 7 are finished and pushed.** The final whole-branch review ran, its fix wave and one residual keyring fix landed and were reviewed. Nothing is merged._

**To resume (next plan):**
> Songies Plans 6 and 7 are done (branches `plan-6-song-menu`, `plan-7-youtube-login`, pushed). Next: the live sign-in check and device checks in docs/manual-test-checklist.md, then write Plan 8 (synced lyrics). Read docs/PROGRESS.md. Don't merge.

## Where things are
- **Plan 6, one song menu everywhere:** done and reviewed, on branch `plan-6-song-menu` (`60ba176`, `80d415f`).
  - Long-press, right-click or ⋯ opens the same menu on any song: Play next, Add to queue, Add to playlist, Start radio, Go to artist/album, Download, and Remove from this playlist.
  - Plan 6 was a small change, so it has no plan file.
- **Plan 7, YouTube sign-in:** branch `plan-7-youtube-login`, made from `plan-6-song-menu`.
  - Spec: [YouTube sign-in design](superpowers/specs/2026-10-27-songies-youtube-login-design.md). Plan: [Plan 7](superpowers/plans/2026-10-28-songies-plan-7-youtube-login.md).
  - Tasks 1–7 are done, each reviewed and fixed. HEAD is `23c227c`.
  - 1,430 tests pass and `flutter analyze` is clean. The APK (81.2 MB) and the Linux release builds succeed.
- **Ledger:** `.superpowers/sdd/2026-10-28-songies-plan-7-youtube-login/progress.md` (git-ignored). It holds the conflict scan, rulings R1–R7, and every deferred minor. `constraints.md` sits next to it.
- **Done since the stop:** the final review (no secret leak), one fix wave (`bfc2f03`: YouTube-only cookies R8, bad cookie values, keyring hiccups, recovery from a locked keyring, all routes on "Sign in again", and the small items), and a residual fix (`03a0033`: a failed keyring check is never cached). 1,457 tests pass; APK and Linux builds succeed.
- **Was left to do (now done):**
  1. The final whole-branch review on the most capable model. It was stopped before it reported, and it was read-only, so there's nothing to undo.
  2. One fix round, which also covers a small Task 7 doc item: the Plan 6 entry in PROGRESS.md leaves out Go to artist/album, the queue, YouTube Music pages and Now Playing ⋯.
  3. A scoped review of that fix.
  4. Ask before pushing `plan-6-song-menu` and `plan-7-youtube-login`.
- **`stash@{0}`** holds unrelated `dart format` changes from Task 6. They're not needed. Drop it whenever you like.

## Not verified live (manual checks pending)
- No real sign-in has been run. The probe (`tool/innertube_auth_probe.dart`; steps in `docs/innertube-notes.md`) and the per-platform items in `docs/manual-test-checklist.md` cover:
  - the personal feed;
  - plays landing in your YouTube history;
  - expiry detection;
  - the Windows build. It now has two WebView2 plugins and needs nuget.exe plus the WebView2 runtime.

## Decisions made on your behalf (cost if wrong)
- **R1:** after a play counts (30 s), one extra signed-in request fetches account tracking URLs. *If wrong:* one request per counted play.
- **R2:** the Linux packages were needed, and you installed them (libsecret-devel, webkit2gtk4.1-devel). *If wrong:* nothing.
- **R3:** the browser sign-in looks in Flatpak profiles (all your browsers are Flatpaks). *If wrong:* a few extra path checks.
- **R4:** real signed-in responses are never saved as test data, because they'd reveal your listening taste. *If wrong:* the parsers are tested on hand-made data.
- **R5:** nothing touches the keyring at app start. It's read the first time the session is needed. *If wrong:* the first signed-in Home load waits for the keyring once.
- **R6:** only an explicit "signed out" marker or HTTP 401/403 expires the sign-in. *If wrong:* a session that has truly expired but sends no marker shows the regular feed with no notice.
- **R7:** the browser sign-in asks first and reads nothing until you pick a browser. *If wrong:* the list can include a browser that isn't signed in to YouTube.
- **R8 (final review):** the stored session holds only the cookies a browser sends to music.youtube.com, no google.com cookies; signed-in reports go only to https YouTube hosts. *If wrong:* if YouTube needs a google.com cookie, Home comes back signed out (shown as the regular feed, no error).

## Worth your attention
- **Something got deleted:** during Task 6, a test deleted two leftover WebKit folders from the probe (`~/.local/share/com.songies.songies` and `~/.cache/com.songies.songies`). Your Songies data in `~/.local/share/songies` is intact, and the test can no longer reach real folders.
- **Beta packages:** `flutter_inappwebview` is pinned to beta platform packages, because the stable 6.1.5 breaks Android release builds. There's a TODO to move to the stable 6.2.x once it's out.
- **The probe needs your cookies:** to run it later, export `cookies.txt` from your signed-in browser to `/home/dencho/yt-cookies.txt`, and delete the file afterwards.
