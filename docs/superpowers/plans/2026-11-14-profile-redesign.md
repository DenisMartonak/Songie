# Profile Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One profile view, used for your own profile and a friend's, with real artist photos and song covers, minutes, chart and period picker, in a phone and a PC layout. Friends see the stats you see, published hourly.

**Architecture:** `PeriodStats` stays the one stats model; `ArtistStat`/`SongStat` gain optional URL fields. A new `StatsSummary` (four `PeriodStats` plus a date) replaces `TopSummary` in the `activity.top` jsonb, keeping the old keys for old readers. An `ArtistPhotos` cache (settings repo) supplies photo and browse id per artist name. A new `ProfileView` renders a `ProfileSource` (mine / a friend) and replaces the bodies of `ProfilePage` and `FriendPage`.

**Tech Stack:** Flutter, Riverpod, go_router, drift `SettingsRepository`, Supabase RPCs (plpgsql). Tests: `flutter_test` with `UiHarness` / `uiTest`, fakes in `test/helpers/`.

**Spec:** `docs/superpowers/specs/2026-11-14-profile-redesign-design.md`

Run Flutter as `export PATH=$HOME/development/flutter/bin:$PATH` first. Never boot the Android emulator.

## Global Constraints

- Colors only from the theme (`SongiesColors`, `ColorScheme`); no hard-coded hues. The glow is the accent (`colorScheme.primary`) at low opacity.
- Wide (PC) layout when the view's own width is ≥ `ProfileView.wideBreakpoint = 840`; else the phone layout. Content max width: phone `720`, wide `1200`, centered. The scroll view spans the full width so the scrollbar sits at the window edge.
- Lists show 5 rows, then all 10 after "Show more" (phone: full-width outlined button under the list; wide: text button in the list header). Headings: `Top 10 artists`, `Top 10 songs`.
- Artist rows: round photo, name, `N min`. Song rows: square cover, title, artist, `N plays`. Phone: rank on the left; wide: rank as a large muted number on the right.
- Totals: phone card "Minutes listened" + number + `min`; wide: big number + `minutes listened in the last <period>` (`7 days`, `30 days`, `6 months`, `12 months`).
- Own profile buttons: `Edit profile` (FilledButton) and a `⋯` menu with `Log out`, `Delete account`. Friend: only `⋯` with `Remove friend`.
- Friend count line: `1 friend` / `N friends`; hidden until known.
- Messages: `<name> doesn't share their stats`; `No stats from <name> yet`; `Updated <relative>` when the friend's summary is more than a day old (e.g. `Updated 3 weeks ago`, `Updated yesterday`).
- Privacy switch copy: title `Share my stats with friends`, subtitle `Minutes, chart and top 10 artists and songs`.
- Payload: `activity.top` ≤ 64 kB (`StatsSummary.maxBytes = 60000` client-side margin).
- Photo lookups at most once per hour (`ArtistPhotos.every = Duration(hours: 1)`); failures are not cached.

## Review Focus

1. **A friend on an older app version** (payload has only `artists`/`songs` names): the page shows a 30-day top 10 without numbers, chart or picker, never a crash or "No stats". (Task 2 parse test; Task 6 widget test.)
2. **A malformed or partial payload** (a period missing, a song without title, bucket not a list): skipped entry by entry, the rest shows. (Task 2 test.)
3. **Very long names at the 840 px boundary and on a 360 px phone**: no overflow; names ellipsize. (Task 5 test pumps both widths with a 200-char name and checks `tester.takeException()` is null.)
4. **Offline / YouTube Music failing during photo lookup**: the profile still renders with placeholders, nothing is cached, the next pass retries. (Task 3 test.)
5. **Removing a friend from their page**: after Remove, the page pops back and does not flash "Not in your friends". (Task 7 test.)

---

### Task 1: Server migration

**Files:**
- Create: `supabase/migrations/20261118120000_profile_stats.sql`

**Interfaces:**
- Produces: RPC `publish_top(p_top jsonb)` with a 65536-byte limit; `friend_activity()` returning `(user_id uuid, now_playing jsonb, now_updated_at timestamptz, room_code text, top jsonb, share_top boolean)`; `friend_count(p_user uuid) returns integer`.

- [ ] **Step 1: Write the migration**
  - `create or replace function public.publish_top` — same body as in `20261115120000_friend_activity.sql`, limit `65536`.
  - `drop function public.friend_activity();` then recreate it with the extra column `a.share_top` (the flag itself, unmasked; `top` stays masked by it).
  - `friend_count(p_user uuid)`: `security definer`, `set search_path = ''`, `stable`. Returns the count of `friendships` with `status = 'accepted'` and `p_user` in either side, when `p_user = auth.uid()` or an accepted friendship joins the caller and `p_user`; otherwise null.
  - Revoke from `public, anon, authenticated`; grant execute to `authenticated` (as the earlier migrations do).
- [ ] **Step 2: Test it in podman** (recipe in the memory note: `postgres:16-alpine`, stubs for `auth.users`, `auth.uid()`, `profiles`, `extensions` with pgcrypto, `realtime`). Apply all migrations in order; check: `friend_activity` returns `share_top`; `friend_count` returns the count for self and for a friend, null for a stranger; a 40 kB `publish_top` succeeds, 70 kB fails with `too_large`.
- [ ] **Step 3: Commit** `feat(server): stats sharing flag, friend count, 64 kB top (SON-39)`.

### Task 2: StatsSummary model and backend

**Files:**
- Modify: `lib/stats/stats_models.dart` (fields), `lib/friends/activity_backend.dart`, `lib/friends/friends_backend.dart`, `lib/friends/friends_service.dart` (only for the new fields), `test/helpers/fake_activity_backend.dart`, `test/helpers/fake_friends_backend.dart`
- Create: `lib/friends/stats_summary.dart`
- Test: `test/friends/stats_summary_test.dart`, `test/friends/activity_backend_test.dart`, `test/friends/friends_backend_test.dart`

**Interfaces:**
- Produces:
  - `ArtistStat` gains `String? photoUrl`, `String? browseId`; `SongStat` gains `String? videoId` and getter `String? coverUrl` (`https://i.ytimg.com/vi/<id>/hqdefault.jpg`); both get `copyWith` for those fields only.
  - `class StatsSummary { StatsSummary({required DateTime at, required Map<StatsPeriod, PeriodStats> periods, bool legacy = false}); final DateTime at; final Map<StatsPeriod, PeriodStats> periods; final bool legacy; static const maxBytes = 60000; Map<String, Object?> toJson(); static StatsSummary? fromJson(Object? j); }`
  - `FriendActivity.top` (type `TopSummary?`) is replaced by `StatsSummary? stats` and `bool sharesStats` (default true). `TopSummary` is deleted; `NowPlaying` stays.
  - `ActivityBackend.publishTop(StatsSummary summary)`.
  - `FriendsBackend.friendCount(String userId) → Future<int?>` (RPC `friend_count`, `{'p_user': userId}`).

- [ ] **Step 1: Write failing tests** in `stats_summary_test.dart`:
  - `round trip keeps every period`: build a summary for all four periods (total, previousTotal, 2 buckets, 1 artist with photo/browseId/plays/heard, 1 song with videoId) → `fromJson(jsonDecode(jsonEncode(toJson())))` equals field by field; `legacy` false.
  - `json keeps the old keys`: `toJson()['artists']` is `[{'name': ...}]` and `['songs']` is a list of `NowPlaying` json, both from the month period.
  - `old payload reads as legacy month`: `fromJson({'artists': [{'name': 'A'}], 'songs': [{'title': 'T', 'artist': 'B'}]})` → `legacy` true, only `StatsPeriod.month`, one artist `A`, one song `T`, `total == Duration.zero`.
  - `bad entries are skipped`: a v2 payload with a song lacking `title`, an artist with `ms: 'x'`, `buckets: 5`, and no `year` → the good entries parse, `periods` has no `year`, buckets empty.
  - `toJson trims to maxBytes`: a summary with 10 artists/songs of 2000-char names per period → `utf8.encode(jsonEncode(toJson())).length <= StatsSummary.maxBytes`, and the month period's lists are the last to be cut (year trimmed first, then halfYear, then week).
  - Backend: `friendActivity reads share_top` (false → `sharesStats` false; missing → true) and `friendCount calls friend_count`.
- [ ] **Step 2: Run** `flutter test test/friends/` → fails (no `StatsSummary`).
- [ ] **Step 3: Implement.** JSON shape (v2):

```json
{"v": 2, "at": "2026-11-14",
 "periods": {"month": {"total": 0, "prev": 0,
   "buckets": [["2026-10-16", 123456]],
   "artists": [{"name": "", "ms": 0, "plays": 0, "photo": "", "browseId": ""}],
   "songs": [{"title": "", "artist": "", "ms": 0, "plays": 0, "videoId": ""}]}},
 "artists": [{"name": ""}], "songs": [{"title": "", "artist": "", "videoId": ""}]}
```

  `prev` omitted when `previousTotal` is null. Bucket `end` on read = next bucket's start, the last one's = `at + 1 day`. Parsed `SongStat.trackId` = `'yt:<videoId>'` or `'friend:<period>:<index>'`; `mainArtist` = `''`, `artist` = the published artist. Legacy reading makes no buckets.
- [ ] **Step 4: Fix callers** (`friend_page.dart` uses `.top` — switch it to `.stats` minimally so it compiles; the page is replaced in Task 7). Update the fakes.
- [ ] **Step 5: Run** `flutter test test/friends/ && flutter analyze` → pass, no issues.
- [ ] **Step 6: Commit** `feat(friends): full stats summary for friends (SON-39)`.

### Task 3: Artist photos cache

**Files:**
- Create: `lib/stats/artist_photos.dart`
- Modify: `lib/providers.dart` (provider), `lib/data/settings_repository.dart` (key `kArtistPhotos = 'artist_photos'`)
- Test: `test/stats/artist_photos_test.dart`

**Interfaces:**
- Consumes: `ArtistStat` from Task 2.
- Produces:
  - `typedef ArtistPhoto = ({String browseId, String? photoUrl});`
  - `class ArtistPhotos { ArtistPhotos({required SettingsRepository settings, required Future<Map<String, ArtistPhoto>> Function() saved, required Future<String?> Function(String trackId) browseIdForTrack, required Future<ArtistPhoto?> Function(String browseId) artist, DateTime Function() now = DateTime.now}); static const every = Duration(hours: 1); ArtistPhoto? of(String name); Stream<void> get changes; Future<void> load(); Future<void> fill(List<ArtistStat> artists, {bool force = false}); List<ArtistStat> apply(List<ArtistStat> artists); }`
  - `artistPhotosProvider` (Provider<ArtistPhotos>) wired with: saved artists from `savedArtistsRepositoryProvider` (name → browseId, thumbnailUrl); `browseIdForTrack` = `libraryRepository.trackById` then `artistLookupProvider.forTrack`; `artist` = `ytmService.artist(browseId)` → `(browseId, page.artist.thumbnailUrl)`, null on error. `artistPhotosChangesProvider` (StreamProvider<int>, a counter of `changes`).

  Note: `artistLookupProvider` lives in `lib/ui/ytm/artist_lookup.dart`; importing it from `providers.dart` is fine if it doesn't create an import cycle, otherwise move `ArtistLookup` + its provider to `lib/innertube/artist_lookup.dart` and re-export from the old file.

- [ ] **Step 1: Write failing tests:**
  - `saved artist wins without a lookup`: saved has `A` → `fill([A])` makes no `browseIdForTrack` call; `of('A')` is the saved photo.
  - `looks up through the sample track`: `fill` → `browseIdForTrack(sampleTrackId)` → `artist(id)`; `of` returns it; `changes` emits once.
  - `kept across instances`: a second `ArtistPhotos` on the same settings, after `load()`, answers `of` without lookups.
  - `failures are not cached`: `artist` throws / returns null → `of` null; a forced second `fill` asks again.
  - `at most once an hour`: two `fill`s 10 min apart → one pass; at 61 min → second pass; `force: true` bypasses.
  - `apply` fills `photoUrl`/`browseId` on known names and leaves others unchanged.
- [ ] **Step 2: Run** `flutter test test/stats/artist_photos_test.dart` → fails.
- [ ] **Step 3: Implement.** Stored as one JSON map `name → {b, p}`; names compared as given (the stats already use the recorded spelling). Artists without a sample track and not saved are skipped. Lookups run one at a time.
- [ ] **Step 4: Run** the test → pass.
- [ ] **Step 5: Commit** `feat(stats): artist photos cache (SON-39)`.

### Task 4: Publisher sends the full summary

**Files:**
- Modify: `lib/friends/activity_publisher.dart`, `lib/providers.dart` (`activityPublisherProvider`), `lib/ui/settings/privacy_settings.dart` (copy)
- Test: `test/friends/activity_publisher_test.dart`, privacy settings test if it asserts the copy (`grep -rn "Share my top" test`)

**Interfaces:**
- Consumes: `StatsSummary` (Task 2), `ArtistPhotos.fill/apply` (Task 3).
- Produces: `ActivityPublisher(... required Future<StatsSummary?> Function() top ...)` (same parameter name, new type).

- [ ] **Step 1: Update the publisher tests** to the new type; add `publishes all four periods` (fake `top` returns a summary; the fake backend receives it unchanged).
- [ ] **Step 2: Run** → fails to compile; then implement the type change.
- [ ] **Step 3: Wire the provider:** `top` = read the four `stats.period(p)`, `await photos.fill(month+…all artists)`, then build `StatsSummary(at: today local date, periods: {p: stats.copy with apply(artists) and songs with videoId})`. Song `videoId`: `SongStat` gets it from the repository — add `videoId` to `StatsRepository.period` output from the latest snapshot's track when `source == 'yt'` (extend its snapshot query; covered by a new `stats_repository_test` case `songs carry the YouTube video id`).
- [ ] **Step 4: Copy** in Privacy per Global Constraints.
- [ ] **Step 5: Run** `flutter test test/friends test/stats test/ui/settings` → pass.
- [ ] **Step 6: Commit** `feat(friends): publish full stats with pictures (SON-39)`.

### Task 5: ProfileView stats section

**Files:**
- Create: `lib/ui/profile/profile_stats.dart` (picker, totals + chart, top lists, rows, `ProfileArt`)
- Modify: `lib/ui/stats/stats_page.dart` — delete `StatsPage` (unrouted) and `StatsBody`; keep `statsChangeText` and `StatsChart` (move `statsChangeText` to `profile_stats.dart` if nothing else uses `stats_page.dart`, then delete that file).
- Test: `test/ui/profile/profile_stats_test.dart` (move and adapt the `StatsBody` assertions from `test/ui/account/profile_page_test.dart` and any stats page test)

**Interfaces:**
- Consumes: `PeriodStats`, `ArtistStat.photoUrl/browseId`, `SongStat.videoId/coverUrl`, `artistPhotosProvider`.
- Produces:
  - `class ProfileStats extends ConsumerWidget { const ProfileStats({required PeriodStats? stats, required StatsPeriod period, required ValueChanged<StatsPeriod>? onPeriod, required bool wide, required bool mine, String? note}); }` — `onPeriod` null hides the picker (legacy); `note` is the muted `Updated …` line; `mine` decides how rows behave.
  - `class ProfileArt extends StatelessWidget { const ProfileArt({String? url, String? artworkRef, required String seed, required double size, double? radius}); }` — `Image.network` for `url`, else `Artwork(artworkRef, seed: seed)`, falling back to the placeholder on error.
  - Keys: `profile.period.<name>`, `profile.total`, `profile.chart`, `profile.artist.<i>`, `profile.song.<i>`, `profile.artists.more`, `profile.songs.more`.

- [ ] **Step 1: Write failing widget tests:**
  - `shows 5 then 10 after Show more` (both lists, phone and wide).
  - `artist row shows minutes, song row shows plays` (`412 min`, `41 plays`).
  - `wide total reads "minutes listened in the last 30 days"`.
  - `legacy stats: no picker, no total, no chart, names listed`.
  - `own artist row uses the cached photo when known` (an `ArtistPhotos` fake with a URL → an `Image` with `NetworkImage`).
  - `friend song with a video id plays it; without one isn't tappable` (tap → `ytTrackStore.upsertAll` then `playQueue`).
  - `own song row keeps menu and star` (as `_SongRow` today).
  - Review Focus 3: 200-char names at widths 360 and 840 → no exception.
- [ ] **Step 2: Run** → fail.
- [ ] **Step 3: Implement.** Row taps: artist → `openArtist(context, ref, browseId: a.browseId, track: <sample track when mine>, name: a.name)`. Own song rows keep today's behavior (play, menu, star). Friend song with `videoId`: build a `YtmSong(videoId, title, artists: [YtmArtistRef(name: artist)], thumbnailUrl: coverUrl)`, `ytTrackStoreProvider.upsertAll`, `playerInputsProvider.playQueue([track])`.
- [ ] **Step 4: Run** → pass; `flutter analyze` clean.
- [ ] **Step 5: Commit** `feat(profile): stats section with pictures (SON-39)`.

### Task 6: ProfileView header and layout

**Files:**
- Create: `lib/ui/profile/profile_view.dart`, `lib/ui/profile/profile_header.dart`
- Modify: `lib/providers.dart` (`friendCountProvider`)
- Test: `test/ui/profile/profile_view_test.dart`

**Interfaces:**
- Consumes: `ProfileStats` (Task 5), `FriendsBackend.friendCount` (Task 2), `FriendActivity.stats/sharesStats`.
- Produces:
  - `sealed class ProfileSource` with `MyProfile()` and `FriendProfile(String userId)`.
  - `class ProfileView extends ConsumerStatefulWidget { const ProfileView({required ProfileSource source, required List<Widget> actions}); static const double wideBreakpoint = 840; }` — `actions` are the header buttons (Edit profile, ⋯) supplied by the page.
  - `friendCountProvider` = `FutureProvider.autoDispose.family<int?, String>`; for `MyProfile` the count comes from `friendsStateProvider` (friends length) and stays tappable to `/profile/friends` with `FriendDot`.
  - Keys: `profile.name`, `profile.friendCount`, `profile.listening`, `profile.join`, `profile.noShare`, `profile.noStats`, `profile.updated`.

- [ ] **Step 1: Write failing widget tests:**
  - `phone: avatar, name, friends, actions, listening, then stats` (vertical order by `tester.getTopLeft`).
  - `wide: listening sits under the avatar; actions at the far right`.
  - `friend sharing off shows "<name> doesn't share their stats" and no picker`.
  - `friend sharing on with no summary shows "No stats from <name> yet"`.
  - `friend summary two weeks old shows "Updated 2 weeks ago"`; one hour old shows nothing.
  - `friend period picker doesn't change mine` (select 7d on the friend view, `statsPeriodProvider` stays `month`).
  - `Join shows while they host a room` (reuse the `friend.join` behavior from `friend_page.dart`, key `profile.join`).
  - `scroll view spans the window` (the `Scrollable`'s width == the screen width at 1400 px).
  - Legacy friend payload: names listed, no numbers (Review Focus 1).
- [ ] **Step 2: Run** → fail.
- [ ] **Step 3: Implement.** Mine: stats from `periodStatsProvider(statsPeriodProvider)` with `ArtistPhotos.apply` on artists (watch `artistPhotosChangesProvider`) and `fill` once on open. Friend: period in local state (default `month`), stats from `friendsStateProvider.activity[id].stats.periods[period]`; keep `watchClosely()` / `stopWatching` as `FriendPage` does now. Glow: `RadialGradient` of `primary.withValues(alpha: 0.18)` → transparent behind the header. Relative time: days → `yesterday` / `N days ago`, then weeks, then months.
- [ ] **Step 4: Run** → pass.
- [ ] **Step 5: Commit** `feat(profile): one profile view for you and friends (SON-39)`.

### Task 7: Wire the pages

**Files:**
- Modify: `lib/ui/account/profile_page.dart`, `lib/ui/friends/friend_page.dart`
- Create: `lib/ui/account/edit_profile_sheet.dart`
- Test: `test/ui/account/profile_page_test.dart`, `test/ui/account/account_ui_test.dart`, `test/ui/friends/friend_activity_ui_test.dart` (update to new keys)

**Interfaces:**
- Consumes: `ProfileView`, `MyProfile`, `FriendProfile` (Task 6).
- Produces: `Future<void> showEditProfile(BuildContext context)` — a modal bottom sheet (phone) / dialog (wide) with `PictureViewer` entry (tap avatar → `showPictureViewer`), `InlineUsername`, and the email (key `account.email`).

- [ ] **Step 1: Update tests first:** own profile: `profile.edit` opens the sheet showing `account.email`; `profile.menu` → `account.logOut` and `account.delete` keep their flows (unsent check, confirm); no `SyncStatusLine`, no "Account" heading. Friend: `profile.menu` → `friend.remove` confirm → pops (Review Focus 5: no "Not in your friends" frame — keep the last found user while popping). Signed out `/profile` unchanged.
- [ ] **Step 2: Run** → fail.
- [ ] **Step 3: Implement.** `ProfilePage` signed in = `ProfileView(source: MyProfile(), actions: [Edit profile, ⋯])`; back button and busy/error handling stay (error shown under the header). `FriendPage` = `ProfileView(source: FriendProfile(id), actions: [⋯])` with a back button when it can pop; remove `_NowPlayingCard`, `_Heading`, `_Ranked`. Delete `SyncStatusLine` only if nothing else uses it (`grep -rn SyncStatusLine lib`).
- [ ] **Step 4: Run the whole suite** `flutter test` → all pass; `flutter analyze` → no issues.
- [ ] **Step 5: Build** `flutter build linux` (sanity) and `flutter build apk --debug`; `./gradlew --stop` afterwards.
- [ ] **Step 6: Commit** `feat(profile): profile and friend pages use the new view (SON-39)`.
