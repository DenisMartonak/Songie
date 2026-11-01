# Crossfade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Spotify-style crossfade (off by default, 1–12 s) when a song plays to its end, with manual actions cutting the outgoing song and everything else (equalizer, volume, lock screen, stats, play reports) still right.

**Architecture:** A `CrossfadeBackend` implements the existing `AudioBackend` over two inner `JustAudioBackend`s and adds one method, `crossfadeTo`. `PlayerService` decides *when* to fade (natural end, conditions met, next stream already resolved) and switches its current entry at the fade's start; the backend does the *how* (load the idle player, ramp both, release the old one). Any other command during a fade cuts the tail first. With crossfade off, `PlayerService` never calls `crossfadeTo` and the backend forwards to one player, as today.

**Tech Stack:** Flutter 3.47.8, just_audio, Riverpod, fake_async for timing tests.

**Spec:** `docs/superpowers/specs/2026-11-01-crossfade-design.md` (built after `docs/superpowers/plans/2026-11-01-equalizer.md`).

## Global Constraints

- Setting `kCrossfadeSeconds` (int, device-local), `0` = off (default); the UI offers 1–12, default 5 when switched on.
- Fade length = `min(setting, current duration ÷ 3, next duration ÷ 3)`; no fade if that is under 1 s.
- Fades only on a natural end with a following song (queue next, repeat-all wrap, radio next). Never on Next/Previous/tap/seek, repeat-one, last song with repeat off.
- Curve: equal-power (outgoing `cos(t·π/2)`, incoming `sin(t·π/2)`), multiplied by the user's volume; volume updates every 50 ms during a fade only (no timer otherwise).
- Manual action mid-fade: outgoing ramps to 0 over 100 ms and stops; the action then applies to the incoming song.
- The incoming song is the current song from the fade's first moment (UI, lock screen, Discord, lyrics).
- If the next song's stream isn't resolved when the fade point arrives, no fade: today's behaviour.
- Crossfade off ⇒ no behaviour change; every existing player test passes unchanged.
- Settings → Playback (from the equalizer plan): `Crossfade` switch, and when on a slider `1 s … 12 s` labelled with the value.
- Run tests with `export PATH=$HOME/development/flutter/bin:$PATH`; the two stats "under 500 ms" tests fail only under full-suite load.

## Review Focus

- Pause in the middle of a fade, wait, resume: both songs resume and the fade finishes with the right remaining time. → Task 2.
- Seek bar dragged during a fade: the outgoing song is cut and the incoming one seeks. → Task 2/3.
- Next song is a YouTube stream that fails to resolve near the end: the current song plays out, then today's skip flow. → Task 3.
- A 20-second song followed by a 3-minute song with crossfade 12 s: fade is 6.67 s. → Task 1.
- Stats: the outgoing song's listen includes the fade seconds it was heard (or up to the cut). → Task 4.

---

### Task 1: Fade math

**Files:** Create `lib/player/crossfade.dart`; Test `test/player/crossfade_math_test.dart`

**Interfaces — Produces:**
- `Duration? fadeLength(int settingSeconds, Duration current, Duration? next)` — null when off, `next` unknown, or result < 1 s.
- `({double outgoing, double incoming}) fadeGains(double t)` — `t` in [0, 1], equal-power.
- `const kFadeTick = Duration(milliseconds: 50); const kCutRamp = Duration(milliseconds: 100);`

- [ ] **Step 1: Failing tests:** `fadeLength(12, 20 s, 180 s)` = 6.667 s (6666 ms ±1); `fadeLength(5, 200 s, 200 s)` = 5 s; `fadeLength(0, …)` null; `fadeLength(5, 2 s, 200 s)` null (0.67 s < 1 s); `fadeLength(5, 200 s, null)` null; `fadeGains(0)` = (1, 0); `fadeGains(1)` = (0, 1) within 1e-9; `fadeGains(0.5)` both ≈ 0.7071.
- [ ] **Step 2: Run** `flutter test test/player/crossfade_math_test.dart` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat: crossfade timing and curve`

### Task 2: CrossfadeBackend

**Files:** Create `lib/player/crossfade_backend.dart`; Modify `lib/player/audio_backend.dart` (doc only), `lib/main.dart` (wrap two `JustAudioBackend`s); Modify `lib/player/equalizer.dart` (Android control applies to both players' equalizers); Test `test/player/crossfade_backend_test.dart`

**Interfaces:**
- Consumes: Task 1; the equalizer plan's `Equalizer`.
- Produces: `class CrossfadeBackend implements AudioBackend { CrossfadeBackend(AudioBackend Function() create); Future<void> crossfadeTo(AudioSourceRef next, Duration fade); bool get fading; }`
  - Starts with one inner backend; creates the second lazily on the first `crossfadeTo`, and disposes the idle one after 30 s unused.
  - `crossfadeTo`: idle backend `setSource(next)`, `setVolume(0)`, `play()`; ramps per `fadeGains` every `kFadeTick` scaled by the user volume; at the end stops and releases the outgoing one. `states` switch to the incoming backend immediately (its position, duration, completed). `errors` from the incoming backend are forwarded; errors from the outgoing one during a fade only end the fade early.
  - `pause()` mid-fade pauses both and freezes the ramp; `play()` resumes both and the ramp continues from where it was.
  - `setSource`, `seek`, `stop` mid-fade: first ramp the outgoing one to 0 over `kCutRamp` and stop it, then apply to the incoming (now only) backend.
  - `setVolume(v)` stores the user volume; mid-fade both players use `v × gain`.
- [ ] **Step 1: Failing tests** (two `FakeAudioBackend`s from `test/player/`, `fakeAsync`): after `crossfadeTo(b, 5 s)`, at 0 / 2.5 / 5 s the outgoing volume is 1 / ≈0.707 / stopped and incoming 0 / ≈0.707 / 1; states come from the incoming fake from t=0; pause at 2 s + 10 s wait + play → fade ends at 15 s wall time; `seek` at 2 s → outgoing volume 0 and stopped by 2.1 s, incoming got the seek; user volume 0.5 → incoming ends at 0.5; no timer runs while not fading (`async.pendingTimers` empty).
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement**; wire in `main.dart` as `CrossfadeBackend(JustAudioBackend.new)`.
- [ ] **Step 4: Run** `flutter test test/player` → PASS.
- [ ] **Step 5: Commit** `feat: a backend that can crossfade between two players`

### Task 3: PlayerService triggers the fade

**Files:** Modify `lib/player/player_service.dart` (`_onBackendState`, `_maybePrefetch`, new `_maybeCrossfade`); Modify `lib/player/audio_backend.dart` (`abstract interface class Crossfader { Future<void> crossfadeTo(AudioSourceRef next, Duration fade); bool get fading; }`, implemented by `CrossfadeBackend`); Test `test/player/player_crossfade_test.dart`

**Interfaces:**
- Consumes: `fadeLength` (Task 1), `Crossfader` (Task 2).
- Produces: `PlayerService(..., {int Function()? crossfadeSeconds})` — read on each tick; `null`/0 = off.
  - When `position >= duration - fade`, the song is ending naturally, the next entry's source is already resolved (the prefetch made it ready; resolve it with `_resolver.resolve` returning instantly from the stream cache), and the backend is a `Crossfader`: call `crossfadeTo(next, fade)` and switch `_state` to the next entry at once (as `_tryStart` does after `setSource`, without `setSource`), firing track-start reporting for it.
  - The outgoing song's completion event (if the backend still emits one) is ignored.
  - Resolve failure or a not-ready stream at the fade point: do nothing; the normal completion flow runs.
- [ ] **Step 1: Failing tests** (fake backend implementing `Crossfader`, fake resolver): setting 5, song 200 s, at 195 s → `crossfadeTo(next, 5 s)` called once and `state.current` is the next song; repeat-one → never called; last song with repeat off → never; `next()` at 190 s → no fade (plain skip); setting 0 → never called and all existing PlayerService tests still pass; next resolve returns `Err` → never called, at 200 s the normal skip flow runs.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test test/player` → PASS.
- [ ] **Step 5: Commit** `feat: songs crossfade into the next when they end`

### Task 4: Heard time, play reports, Settings

**Files:** Modify `lib/player/player_service.dart` (emit the outgoing song's tail), `lib/stats/listen_recorder.dart`, `lib/innertube/play_reporter.dart`; Modify `lib/data/settings_repository.dart` (`kCrossfadeSeconds`), `lib/ui/settings/playback_settings.dart` (switch + slider), `lib/main.dart`; Modify `docs/manual-test-checklist.md` (Crossfade section); Tests: `test/stats/listen_recorder_test.dart`, `test/innertube/play_reporter_test.dart`, `test/ui/playback_settings_test.dart` (extend)

**Interfaces — Produces:** `Stream<({Track track, Duration heard})> PlayerService.fadeTails` — one event when an outgoing song finishes fading or is cut, with the seconds it played during the fade. `ListenRecorder` adds it to that song's listen; `PlayReporter` adds it to that song's watch time.
- [ ] **Step 1: Failing tests:** a 5 s fade completing → the outgoing listen's heard time grows by 5 s; cut at 2 s → by 2 s; a song that only reaches 30 s heard through its tail still counts as a play; Settings shows `Crossfade` off, switching on shows the slider at `5 s` and stores `5`, dragging to 12 stores `12`, switching off stores `0`.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Full suite** `flutter analyze && flutter test` → clean; all pass except the two known stats timing tests.
- [ ] **Step 5: Commit** `feat: crossfade setting; fades count in stats and play reports`
