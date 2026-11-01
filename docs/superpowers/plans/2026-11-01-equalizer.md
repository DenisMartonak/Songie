# Equalizer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eight equalizer presets in Settings → Playback, applied instantly on Android (system equalizer) and on desktop (mpv's equalizer filter), with Windows falling back to "Not available on Windows yet" if its libmpv lacks the filter.

**Architecture:** Presets are pure data (`EqPreset` → ten gains). An `Equalizer` interface has two implementations: `AndroidEqualizerControl` (just_audio's `AndroidEqualizer` in the player's `AudioPipeline`) and `MpvEqualizerControl` (a labelled `lavfi` equalizer chain set once per mpv player, gains changed with `af-command`). A patched copy of `just_audio_media_kit` under `packages/` exposes its mpv players. A device-local setting holds the preset; a Riverpod notifier applies it.

**Tech Stack:** Flutter 3.47.8, just_audio 0.10.x, just_audio_media_kit 2.1.0 (patched), media_kit, Riverpod, drift settings.

**Spec:** `docs/superpowers/specs/2026-11-01-equalizer-design.md`

## Global Constraints

- Presets, in this order: Off, Bass boost, Vocal, Rock, Pop, Classical, Electronic, Acoustic. Gains exactly as the spec's table (Off = all 0).
- Reference bands (Hz): 31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000.
- Per device, not synced (the `Settings` table is device-local). Key `kEqPreset`, value the preset's `name` (enum name), default `off`.
- Switching is seamless: no `setSource`, no restart; desktop changes gains with `af-command`, never by resetting `af` while playing.
- Settings section title `Playback`; row title `Equalizer`, subtitle the preset's label; on Windows without the filter the subtitle is `Not available on Windows yet` and the row is disabled.
- `just_audio_media_kit` patch: only what this plan adds; a `PATCHED.md` next to it says the upstream version (2.1.0) and why.
- Run tests with `export PATH=$HOME/development/flutter/bin:$PATH`; the two stats "under 500 ms" tests fail only under full-suite load.

## Review Focus

- Preset changed while nothing is playing, then a song starts: the new song gets the preset. → Task 3.
- just_audio rebuilds the mpv player after `stop()` (queue end, then play again): the filter is set on the new player too. → Task 2.
- An Android device reporting 5 bands with a ±15 dB range, and one reporting 10 bands with ±12 dB: gains map by nearest centre and are clamped. → Task 1.
- Windows libmpv without the `equalizer` filter: setting `af` fails; the app keeps playing with no filter and Settings shows the Windows fallback. → Task 2.
- Bass boost at full volume clipping: a preamp of minus the largest positive gain ÷ 2 (dB) is applied. → Task 1.

---

### Task 1: Presets and band mapping

**Files:**
- Create: `lib/player/eq_presets.dart`
- Test: `test/player/eq_presets_test.dart`

**Interfaces:**
- Produces:
  - `enum EqPreset { off, bassBoost, vocal, rock, pop, classical, electronic, acoustic }` with `String get label` (`Off`, `Bass boost`, `Vocal`, `Rock`, `Pop`, `Classical`, `Electronic`, `Acoustic`) and `List<double> get gains` (10 values, spec table).
  - `const kEqBandsHz = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];`
  - `double eqPreampDb(EqPreset p)` = `-(max positive gain) / 2`, 0 when none.
  - `List<double> mapGains(EqPreset p, List<double> bandCentersHz, {required double minDb, required double maxDb})` — for each target band, the gain of the nearest reference band (by log-frequency distance), clamped.
  - `EqPreset eqPresetFromName(String? name)` — unknown or null → `off`.

- [ ] **Step 1: Write the failing tests**
  - Every preset has 10 gains; `off` is all zeros; `bassBoost.gains.first == 6`.
  - `mapGains(EqPreset.bassBoost, [60, 230, 910, 3600, 14000], minDb: -15, maxDb: 15)` → `[5, 2, 0, 0, 0]`.
  - `mapGains(EqPreset.electronic, [31.0, 16000.0], minDb: -3, maxDb: 3)` → `[3, 3]` (clamped).
  - `eqPreampDb(EqPreset.bassBoost) == -3`; `eqPreampDb(EqPreset.classical) == 0`.
  - `eqPresetFromName('rock') == EqPreset.rock`; `eqPresetFromName('nope') == EqPreset.off`.
- [ ] **Step 2: Run to see them fail.** `flutter test test/player/eq_presets_test.dart` → FAIL (missing file).
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** → PASS.
- [ ] **Step 5: Commit** `feat: equalizer presets`

### Task 2: Desktop equalizer through mpv

**Files:**
- Create: `packages/just_audio_media_kit/` (copy of 2.1.0 from the pub cache, plus `PATCHED.md`)
- Modify: `pubspec.yaml` (`just_audio_media_kit: path: packages/just_audio_media_kit`)
- Patch: `packages/just_audio_media_kit/lib/just_audio_media_kit.dart`, `lib/mediakit_player.dart`
- Create: `lib/player/equalizer.dart`
- Test: `test/player/mpv_equalizer_test.dart`

**Interfaces:**
- Patch produces (in `JustAudioMediaKit`): `static void Function(Player player)? onPlayerCreated;` called right after each `MediaKitPlayer` builds its `Player`, and `static Iterable<Player> get livePlayers` (players not yet disposed).
- Produces:
  - `abstract class Equalizer { Future<bool> get available; Future<void> apply(EqPreset preset); }`
  - `class MpvEqualizerControl implements Equalizer { MpvEqualizerControl({required MpvCommands mpv}); }` where `abstract class MpvCommands { Future<void> setFilter(Object player, String af); Future<void> command(Object player, List<String> args); Iterable<Object> get players; set onPlayerCreated(void Function(Object player)? f); }` with a real implementation over the patched package (`NativePlayer.setProperty` / `NativePlayer.command`).
  - Filter string built by `String mpvEqFilter()`: `@songieseq:lavfi=[equalizer=f=31:t=o:w=1:g=0,equalizer=f=62:...,volume=0dB]` — ten `equalizer` stages (one octave wide each) plus a `volume` stage for the preamp, labelled `songieseq`.
  - `apply(p)` sends, for each live player, `af-command songieseq g <gain> <stage index>`... per band and the preamp `volume`; the exact lavfi command syntax is checked against mpv's manual in Step 3. New players get `setFilter` then the current gains from `onPlayerCreated`.
  - `available` is false when `setFilter` throws (no `equalizer` filter in this libmpv); then `apply` is a no-op.
- [ ] **Step 1: Write the failing tests** (fake `MpvCommands` recording calls)
  - `mpvEqFilter()` starts with `@songieseq:lavfi=[`, has 10 `equalizer=f=` stages in `kEqBandsHz` order and ends with `volume=0dB]`.
  - A player created after `apply(EqPreset.rock)` receives `setFilter(mpvEqFilter())` then commands carrying Rock's gains.
  - `apply(EqPreset.off)` on a live player sends all-zero gains (it never clears `af`).
  - `setFilter` throwing → `available` completes false, later `apply` sends nothing, no exception escapes.
- [ ] **Step 2: Run to see them fail.** → FAIL.
- [ ] **Step 3: Implement** (patch, `MpvEqualizerControl`, the real `MpvCommands`).
- [ ] **Step 4: Run** `flutter test test/player` and `flutter analyze` → PASS / clean.
- [ ] **Step 5: Commit** `feat: desktop equalizer through mpv's filter`
- [ ] **Step 6: Windows check (needs the user's PC).** Ask the user to run `flutter run -d windows`, pick Rock in Settings, and say whether the sound changes. If `available` is false there, Task 3's Windows fallback applies; record the result in the spec.

### Task 3: Android equalizer, setting, and Settings row

**Files:**
- Modify: `lib/player/equalizer.dart` (`AndroidEqualizerControl`)
- Modify: `lib/player/just_audio_backend.dart` (create the `AudioPlayer` with `AudioPipeline(androidAudioEffects: [eq])` on Android only)
- Modify: `lib/data/settings_repository.dart` (`kEqPreset`), `lib/providers.dart` (`equalizerProvider`, `eqPresetProvider`), `lib/main.dart` (wire, apply the stored preset at start)
- Create: `lib/ui/settings/playback_settings.dart` (section `Playback` with the Equalizer row and picker); Modify: `lib/ui/settings/settings_page.dart` (place it before `Appearance`)
- Modify: `docs/manual-test-checklist.md` (Equalizer section)
- Test: `test/player/android_equalizer_test.dart`, `test/ui/playback_settings_test.dart`

**Interfaces:**
- Consumes: `EqPreset`, `mapGains`, `eqPreampDb` (Task 1); `Equalizer`, `MpvEqualizerControl` (Task 2).
- Produces:
  - `class AndroidEqualizerControl implements Equalizer { AndroidEqualizerControl(AndroidEqualizerPort port); }` with `abstract class AndroidEqualizerPort { Future<({List<double> centersHz, double minDb, double maxDb})> bands(); Future<void> setEnabled(bool on); Future<void> setBandGain(int i, double db); }` (real port over just_audio's `AndroidEqualizer`). `apply(off)` disables it; other presets enable it and set `mapGains` + preamp folded into each band.
  - `final eqPresetProvider = NotifierProvider<EqPresetNotifier, EqPreset>` — `Future<void> select(EqPreset p)` stores `kEqPreset` and calls `Equalizer.apply`.
- [ ] **Step 1: Write the failing tests**
  - Android: fake port with 5 bands → `apply(EqPreset.bassBoost)` enables and sets 5 gains equal to `mapGains(...)`; `apply(off)` → `setEnabled(false)`.
  - Settings (`UiHarness`): Playback section shows `Equalizer` with subtitle `Off`; picking `Rock` → subtitle `Rock`, stored setting `rock`, the fake `Equalizer` got `apply(rock)`.
  - Settings with an `Equalizer` whose `available` is false on Windows → subtitle `Not available on Windows yet`, row disabled.
  - Start-up: stored `vocal` → the fake `Equalizer` receives `apply(vocal)` before the first song plays.
- [ ] **Step 2: Run to see them fail.** → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the full suite.** `flutter analyze && flutter test` → clean; all pass except the two known stats timing tests.
- [ ] **Step 5: Commit** `feat: equalizer presets in Settings`
