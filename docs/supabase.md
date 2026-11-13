# Supabase setup

Songies accounts run on the Supabase project `dxxbowrmuxtzwrhmulnx` (free tier). Do these steps once. The database part is in the repo (`supabase/migrations/`, with the CLI's `supabase/config.toml`); the rest are dashboard settings that can't live in the repo.

The dashboard moves things around. If a menu name below differs, search for it in the dashboard's settings.

## 1. Apply the database migration

Either with the Supabase CLI (version 3; run from the repo folder, logged in as you):

```
npx supabase@3 login
npx supabase@3 link --project-ref dxxbowrmuxtzwrhmulnx
npx supabase@3 db push --remote
```

1. `login` opens the browser so you can sign in to Supabase.
2. `link` connects the repo folder to the project. If it asks for the database password, use the one you set when you created the project (you can reset it in the dashboard under Project Settings, Database). The CLI keeps the link in `supabase/.temp/`, which is git-ignored. Never write the password into the repo.
3. `db push --remote` applies the migrations in `supabase/migrations/` to the project. Without `--remote`, CLI version 3 pushes to a local database instead.

Or by hand: open the dashboard, SQL Editor, New query, paste the whole of `supabase/migrations/20261105120000_accounts.sql`, and press Run. It should finish with "Success. No rows returned". Then do the same with each later file in `supabase/migrations/`, oldest first (the file names start with the date).

Either way the first migration creates the `profiles` table, the sign-up trigger, the `username_available` and `delete_my_account` functions, and the public `avatars` storage bucket with its rules. Run each migration only once; a second run fails because its tables already exist. Later migrations go in the same folder and are pushed the same way (`db push --remote` applies only the ones the project doesn't have yet).

### Cloud sync (`20261106120000_cloud_sync.sql`)

The second migration adds what cloud sync needs:

- The `sync_rows` table: every synced row of every account (tracks, playlists and their entries, YouTube "seen" marks, themes, fonts, lyrics, listens), one row per account, table and id. A signed-in user can read only their own rows and can't write the table directly.
- `push_rows` (upload up to 500 rows; a row replaces the stored one only when its clock is newer) and `pull_rows` (the rows changed since the last pull, 500 at a time). `push_rows` also refuses a row over 256 KB and a clock more than a day ahead of the server's time. Each row carries its app version's row format (`fmt`); `push_rows` never replaces a row of a newer format, so an older app can't drop fields it doesn't know. A device that pulls a newer-format row shows "Update Songies to keep syncing" and takes it after its update.
- Every write to `sync_rows` must go through `push_rows`. Don't edit the table by hand in the Table Editor or SQL editor (except to look): `push_rows` hands out the change numbers devices pull by one push at a time per account, and a write that skips it can be missed by devices for good.
- A Realtime notice, so a change on one device reaches the others while they run: after each push the database sends a Broadcast message on the private channel `sync:<user id>` saying only "something changed" (the newest change number), and the devices then pull. A user can listen only on their own channel, and no app can send on it. The migration sets this up (a trigger and a rule on `realtime.messages`); there's nothing to switch on in the dashboard (but Realtime's "Allow public access" should be off; see Remote control below). `sync_rows` is deliberately not in the `supabase_realtime` publication: table-change events don't apply the row rules to deletions, so deleting an account would tell every listener which rows it had.
- The private `sync-files` storage bucket for font files and artwork that can't be fetched again, each user only inside their own `<user id>/` folder. Uploads also need the user's profile, so a device still holding a sign-in token after its account was deleted can't put files back. Files are at most 10 MB and must be fonts (TTF/OTF) or JPEG, PNG or WebP images. A font or cover over 10 MB doesn't sync: it stays on the device it was added on (the app skips it and logs a warning).

Deleting an account (`delete_my_account`) deletes its `sync_rows` too. The user's `sync-files` folder is deleted by the app just before, with cloud sync on that device stopped first; if that fails, the account is not deleted and sync starts again.

### Remote control (`20261107120000_remote_control.sql`)

The third migration adds two rules on `realtime.messages` and nothing else (no table, nothing stored). A signed-in user can join, receive on and send on (Broadcast and Presence) only the private channel `remote:<their user id>`; that is how a user's devices see each other and control each other's playback. The `sync:<user id>` topic and its rule are unchanged. There's nothing to switch on in the dashboard, but check that Realtime's "Allow public access" is off (Realtime settings): the rules apply to private channels only, and with public access on, anyone could join `remote:<user id>` as a public channel and bypass them. The app always joins as private.

### Listen together (`20261109120000_listen_together.sql`)

The fourth migration adds rooms: a host opens one, friends join with its 8-character code (shown as `XXXX-XXXX`), and everyone hears the same song. Apply it like the others (once, after the remote control one).

- The `rooms` table (id, code, host, created and ended times) and the `room_members` table (who is in which room, the host included). Both have row rules on and no policy or grant: apps never read or write them directly.
- `open_room` (the caller becomes host of a new room with a fresh code, and their other open rooms end), `join_room` (adds the caller by code; fails with `room_not_found`, `room_ended` when the room was ended or is over 24 hours old, or `room_full` at 10 members; joining twice is fine), `leave_room` (a guest leaves; called from the host's own account, which happens when a second device of that account joined as a guest, it changes nothing, so the room stays open), `remove_member` (host only, never the host) and `end_room` (host only: marks the room ended and deletes its members). All are `security definer`, callable by signed-in users only.
- `room_is_open` (not ended and under 24 hours old; the one test everything uses), `room_of_topic`, `is_room_member` and `is_room_host`: helpers the Realtime rules use, because the tables have no policies a rule could read through.
- Two rules on `realtime.messages` for the private channel `room:<room id>`: a member of an open room can receive and send (Broadcast and Presence), any event. Nothing about what plays is stored; it all travels on that channel. As with remote control, Realtime's "Allow public access" must be off.
- Known limit: the server checks only that a sender is a member of an open room. Realtime checks the rules when a client joins the channel, not per message, so any member could pose as the host (send `state`, `roles`, `kick` or `end`) or as another guest (the `from` device id in a `request`). Broadcasts carry no verified sender, so the app can't tell a real host message from one another member sent either. Rooms are for friends, so this is accepted. Likewise, removing someone or ending the room cuts off an already-connected client only when it reconnects or refreshes its token; the `kick` and `end` messages are cooperative.

After applying it, check by hand (the migration has not been tried on the project yet). You need two accounts, A and B; in the SQL editor, run as each with `set role authenticated; select set_config('request.jwt.claim.sub', '<user id>', false);` (user ids are under Authentication, Users), or use two signed-in app instances for the Realtime part.

1. As A: `select * from open_room();` returns a room id and an 8-character code (different every time) from `ABCDEFGHJKMNPQRSTUVWXYZ23456789`. Calling it again ends the first room (its `ended_at` is set, as seen from the SQL editor's default role) and returns a new one.
2. As B: `select join_room('<code>');` returns the room id. With a lowercase code, a dash or a space in the middle it works too. `join_room('ZZZZZZZZ')` fails with `room_not_found`.
3. As A: `select end_room('<id>');` then as B `join_room('<code>')` fails with `room_ended`. B calling `end_room` or `remove_member` on A's room fails with `not_host`.
4. `room_full`: with ten accounts (or by inserting nine extra `room_members` rows from the default role) in a room, the eleventh `join_room` fails with `room_full`.
5. Same account on two devices: A opens a room on one device and joins it from a second device signed in as A, then leaves on the second device (`select leave_room('<id>');` as A). The room stays open: B can still `join_room('<code>')`, and A's `room_members` row is still there.
6. As B: `select * from rooms;` and `select * from room_members;` fail with permission denied.
7. Realtime Inspector (dashboard, Realtime, Inspector; pick a user's access token, turn Private on) on `room:<room id>`: A and B can both join and receive. A message with event `request` from B arrives for A. A third account C, not in the room, can't join the topic. After A ends the room, nobody can newly join it (a client already connected may keep receiving until it reconnects).

### Saved artists (`20261113120000_saved_artists.sql`)

The fifth migration lets cloud sync carry saved artists. Apply it like the others (once, after the listen together one), and before releasing the app version that saves artists.

- It adds `saved_artists` to the table names `sync_rows` accepts (the `sync_rows_tbl_rule` check, dropped and added again) and to the list in `push_rows` (replaced with the same body otherwise). Nothing else changes; `pull_rows` and the Realtime notice name no tables.
- Until it is applied the server refuses saved-artist rows as invalid, and the app skips refused rows for good, so apply it first.

### Friends (`20261114120000_friends.sql`)

The sixth migration lets accounts become friends: one asks, the other accepts. Apply it like the others (once, after the saved artists one), and before releasing the app version with friends.

- The `friendships` table: one row per pair of accounts, `pending` (a request from `requester` to `addressee`) or `accepted`. A unique index on the unordered pair keeps A→B and B→A from both existing. Rows go when either account is deleted.
- Row rules: a signed-in user can read only the rows they are in. There is no insert, update or delete grant; apps change rows only through the functions.
- `send_friend_request` (a new request, or accepts theirs when the other person already asked; returns `pending` or `accepted`; fails with `self_request` or `unknown_user`), `accept_friend_request` (only the person asked; fails with `not_requested`) and `remove_friend` (deletes the pair's row either way round: declines, cancels or unfriends). All are `security definer`, callable by signed-in users only, and take a lock on the pair so crossed requests sent at once end as one accepted row.
- Finding people needs nothing new: profiles (username and picture) were already readable by every signed-in user.

After applying it, check by hand. You need three accounts, A, B and C; in the SQL editor run as each with `set role authenticated; select set_config('request.jwt.claim.sub', '<user id>', false);`.

1. As A: `select send_friend_request('<B>');` returns `pending`. As B: `select * from friendships;` shows the row. As C it shows nothing.
2. As B: `select accept_friend_request('<A>');` and the row's status is `accepted`. As A: `select accept_friend_request('<B>');` fails with `not_requested`.
3. Crossed requests: as C `send_friend_request('<A>')` returns `pending`; then as A `send_friend_request('<C>')` returns `accepted`, and there is one row for A and C.
4. As A: `send_friend_request('<A>')` fails with `self_request`; `send_friend_request(gen_random_uuid())` fails with `unknown_user`.
5. As A: `insert into friendships values (...)`, `update friendships set status = 'accepted'` and `delete from friendships` all fail with permission denied.
6. As A: `select remove_friend('<C>');` removes their row; calling it again is fine. Deleting account B (Authentication, Users) removes the A–B row.

### Friend activity (`20261115120000_friend_activity.sql`)

The seventh migration lets friends see what each other is listening to, their top 10 of the last 30 days, and join a friend's room. Apply it like the others (once, after the friends one), and before releasing the app version with friend activity.

- The `activity` table: one row per account with two switches (`share_listening`, `share_top`, both on by default), what it plays now and when that was published, the code of the room it hosts, and its top 10. Rows go with the account. A signed-in user reads only their own row; there is no write grant.
- `my_sharing` (the caller's switches; both on with no row yet), `set_sharing` (sets them; one turned off clears what it covers at once), `publish_now_playing` and `publish_top` (do nothing while the matching switch is off) and `friend_activity` (each accepted friend's row, with every part the friend doesn't share left empty). All are `security definer`, callable by signed-in users only. `are_friends` is a helper apps can't call.
- Nothing is pushed live: friends' apps ask every few minutes, and every minute while a friends page is open. A "now playing" older than 15 minutes counts as not listening (the app may have closed without clearing it).

After applying it, check by hand with accounts A and B (friends) and C (not a friend), as for friends:

1. As A: `select * from my_sharing();` gives `true, true`. `select publish_now_playing('{"title":"Halo","artist":"Beyonce"}', 'ABCD2345');` then as B `select * from friend_activity();` shows A's song and the room code.
2. As A: `select publish_top('{"artists":[{"name":"Beyonce"}],"songs":[]}');` and B sees it in `friend_activity()`.
3. As A: `select set_sharing(false, true);` A's own row (`select * from activity;`) has no song or room code, and publishing a song again changes nothing. B's `friend_activity()` row for A has no song or room code but still has the top 10.
4. As C: `friend_activity()` has no row for A, and `select * from activity;` shows only C's own row.
5. As A: writing to `activity` directly (insert, update, delete) and `select are_friends(...)` fail with permission denied.
6. Deleting account A removes A's row.

## 2. Email sign-in settings

1. Under Authentication, Sign In / Providers, in the user sign-up settings: allow new users to sign up, and turn Confirm email on.
2. On the same page open the Email provider: it is on.
3. In the Email provider: minimum password length 8.
4. In the Email provider: email OTP expiration 3600 seconds (1 hour). The migration's sign-up trigger and `username_available` free an unconfirmed sign-up's username after `interval '1 hour'`; that must match this expiry, so change both together (a new migration for the SQL).
5. In the Email provider: email OTP length 6.
6. Save.

## 3. Email templates (codes instead of links)

Songies asks for a 6-digit code instead of opening a link, because links can't reliably open the app on Linux and Windows. Under Authentication, Emails, Templates, replace two templates.

"Confirm signup":

- Subject: `Your Songies code`
- Body:

```
<h2>Welcome to Songies</h2>
<p>Your code is:</p>
<p style="font-size: 28px; font-weight: bold; letter-spacing: 4px;">{{ .Token }}</p>
<p>Type it into Songies to confirm your email. It works for 1 hour.</p>
<p>If you didn't sign up for Songies, ignore this email.</p>
```

"Reset password":

- Subject: `Your Songies password reset code`
- Body:

```
<h2>Reset your Songies password</h2>
<p>Your code is:</p>
<p style="font-size: 28px; font-weight: bold; letter-spacing: 4px;">{{ .Token }}</p>
<p>Type it into Songies with your new password. It works for 1 hour.</p>
<p>If you didn't ask for this, ignore this email; your password stays the same.</p>
```

Save each one. The bodies must not contain `{{ .ConfirmationURL }}`; Songies has no use for the link.

## 4. Email sender (before inviting friends)

Supabase's built-in sender only delivers to the email addresses of members of the project's organization (your team), and only about 2 emails an hour. That's fine for testing with your own address. Friends get no sign-up or reset codes until you set up your own sender (custom SMTP). A free provider such as Resend or Brevo is enough:

1. Create a free account with the provider.
2. Verify a sending address or domain there, following its steps (a domain needs a few DNS records).
3. Find its SMTP details: host, port, user name and password (often an API key used as the password).
4. In Supabase, under Authentication, Emails, SMTP Settings, turn custom SMTP on and paste the host, port, user name and password.
5. Set the sender email to your verified address and the sender name to `Songies`. Save.
6. Under Authentication, Rate Limits, raise the email limit (for example 30 an hour).
7. Sign up a test account with an address outside your team to check a code arrives.

The SMTP password stays in the dashboard only; never put it in the repo.

## 5. Things to know

- Accounts come only from the app: a new account needs a username in its sign-up data, so the dashboard's Add user (and any anonymous or OAuth sign-up, if those are ever turned on) fails with a database error. That's on purpose; create test accounts from the app.
- Unconfirmed sign-ups: a sign-up whose code was never entered (and that never signed in) keeps its username for 1 hour after its last code was sent, the email OTP expiry from step 4. After that, the name counts as free, and the next sign-up that picks it deletes the old unconfirmed account. Supabase itself never deletes unconfirmed accounts. Signing up again with the same unconfirmed email only sends a new code; Supabase keeps the first username and password, so once the code is entered the app sets the password and username typed at that sign-up (if the name was taken meanwhile, it keeps the old one and says so).
- Clearing an unconfirmed sign-up by hand (for example, to free its email or username sooner): open Authentication, Users, find the address (an unconfirmed user shows as waiting for verification, with no confirmed date), open the row's menu (the three dots) and choose Delete user. Its profile goes with it. Only do this for accounts that were never confirmed.
- Free-tier limits: 500 MB database and 1 GB file storage. Synced rows take roughly 1 KB each, indexes included: a test with 10,000 tracks plus 50,000 listens used about 52 MB of database, so a heavy library fits several times over. Playlist entries, themes and lyrics add a little more (lyrics are the biggest per row). Font files and artwork count against the 1 GB storage. Check usage under Project Settings, Usage (or the Reports page).
- First sign-in with a big library: the device sends its whole library up once (500 rows per call), then pulls the account's whole set back down once, the same way. With 10,000 tracks and 50,000 listens that is about 120 calls each way, and "Syncing…" shows until it's done. After that, only changes move. Signing in as a different account and choosing Merge does the same for that account.
- The limits are shared by everyone on the project: there is no quota per user, so one account with a huge library (or a misbehaving app) can use up the database or storage for all. The per-row (256 KB) and per-file (10 MB) caps keep any single upload small, but not the total. Watch the usage page as more friends join.
- Pausing: a free project pauses after 7 days without activity. Songies keeps working while it's paused: signed out as usual, and signed-in devices keep working on their own library and show "Couldn't sync. Will try again." in Settings → Account until the project is restored; their changes go up then. Restore it from the dashboard (the project page shows a Restore button).
- The app's keys: the project URL is on the dashboard's Connect button (and under Project Settings, Data API); the publishable key is under Project Settings, API Keys. Both are public by design and live in `lib/account/supabase_config.dart`.
- Never put the service-role key (or the secret key) in the app or in the repo. It bypasses every rule above. Songies doesn't need it: account deletion goes through `delete_my_account`.
- `supabase/config.toml` only configures a local test database (`npx supabase@3 db start`). Its auth settings match the steps above; don't run `supabase config push` without checking it, because that copies them to the real project.
