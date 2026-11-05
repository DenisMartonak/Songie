# Accounts (Supabase) — step 1: sign up and log in — design

Roadmap item 5, step 1 (`docs/ROADMAP.md`). Agreed with the user on
2026-11-05.

## Why

Songies will get cloud sync of the library (step 2), remote control
(step 3) and listen together (step 4), all through Supabase. They need
an account. Step 1 gives Songies accounts and a simple profile; nothing
else changes yet. The user: "before cloud sync probably nothing special,
just sign up/login, username changing, profile picture changing".

## What it is

- Optional: Songies works fully signed out, as today. No prompt on first
  launch. *(Claude's call: no first-launch prompt.)*
- Sign up and log in with **email and password**. Passkeys wait until
  Supabase's passkey support leaves beta (the user decided; tracked on the
  roadmap as a follow-up).
- Signed in, you can change your **username** and **profile picture**, log
  out, and delete your account.
- The library, playlists and today's home-network sync are untouched.

## Supabase project

- Project URL `https://dxxbowrmuxtzwrhmulnx.supabase.co`, publishable key
  `sb_publishable_qQt5cxct4vp2lo2FqZEGqg_NaK19iPA`. Both are public by
  design and go into the app as constants (not secrets). *(Claude's call:
  constants in a Dart config file rather than build defines, so local
  builds work too.)*
- Free tier. A project pauses after 7 days with no activity; normal use
  keeps it awake. Supabase's built-in email sender allows only a few
  emails an hour and sends from Supabase's address — fine for the author
  and a few friends; a custom SMTP sender can come later.
- Database setup lives in the repo as Supabase migration files
  (`supabase/migrations/…`), applied once by the user with the Supabase CLI
  or by pasting into the dashboard's SQL editor. Dashboard-only settings
  (auth email templates, confirm-email on) are written up in
  `docs/supabase.md` as steps. *(Claude's call.)*

## Sign up

- Email, password (at least 8 characters; Supabase's own minimum set to
  match), username.
- The email must be confirmed before the first login. Supabase emails a
  **6-digit code**; the user types it into Songies. This needs the
  dashboard's "Confirm signup" and "Reset password" email templates changed
  to show `{{ .Token }}` instead of a link (OTP length 6, expiry 1 hour,
  Supabase's defaults); `docs/supabase.md` gives the exact template text.
  The app uses `verifyOTP` (type signup / recovery) and `resend`. Codes rather than
  links, because a link would have to open the app, which is unreliable on
  Linux and Windows. *(Claude's call.)*
- The username is chosen at sign-up and checked for availability as you
  type (debounced), through a database function anyone (even signed out)
  can call that returns only true/false. Listing taken usernames this way
  is accepted: usernames are public to signed-in users anyway.
- The username travels in the sign-up metadata, and a database trigger
  creates the `profiles` row in the same transaction as the account, so an
  account never exists without a username. If someone else took the name
  in the meantime, sign-up fails and the form says "That username was just
  taken". *(Claude's calls.)*
- A sign-up that is never confirmed holds its username only until its
  last code expires (1 hour): after that the name counts as free, and the
  next sign-up that takes it deletes the stale unconfirmed account first.
  The code step has "Use a different email" (back to sign-up, fields
  kept) and "Send a new code". Signing up again with the same unconfirmed
  email only sends a new code: Supabase keeps the first username and
  password, which may be someone else's. So once that code is entered the
  app sets the password typed at this sign-up (Supabase's "same password"
  answer counts as done) and, if the profile's username differs, renames
  it to the typed one; if that name was taken meanwhile it keeps the
  existing one and says "Your account uses the username @<name>. You can
  change it in Settings." If the password can't be set (offline), the app
  logs out and shows the error on the log-in step. The typed password and
  username stay in the form's memory only. A held name is freed only if
  its account never signed in. *(Claude's calls.)*
- Signing up with an email that already has an account: Supabase answers
  without an error but with no identities; the form says "That email
  already has an account. Log in, or reset your password." *(Claude's
  call; it reveals that the address is registered, accepted for a small
  app.)*

## Log in, log out, forgotten password

- Log in with email + password. Supabase refuses an unconfirmed email
  with an "email not confirmed" error; the app then asks for the code
  (with "Send a new code"), sending one right away. Wrong email or password: "Wrong email or
  password."
- "Forgot password?" → enter email → a 6-digit code arrives → enter code
  and a new password → logged in. The code is used up even when the new
  password is refused (same as the old one, or too weak), so that step
  clears the code and offers "Send a new code".
- Log out from the Account section; the session is forgotten on this
  device.
- The session is kept on the device so you stay logged in across restarts,
  stored in the system keyring like the YouTube sign-in (not plain
  preferences). If no keyring is available (some Linux setups), the
  session lives in memory only for that run and a warning is logged.
  *(Claude's call.)*
- Offline: the app works as signed out until it can reach Supabase; it
  never blocks music playback.

## Profile

- **Username:** unique across all accounts, case-insensitive; 3–20
  characters of lowercase letters, numbers, `_` and `.`; can't start or
  end with `.`; changeable any time (no cooldown). *(Rules are Claude's
  call.)*
- **Profile picture:** each upload gets a new file name
  (`<user id>/<timestamp>.jpg`); `avatar_path` is updated, then the old
  file is deleted, so caches never show a stale picture. Pick an image (the existing `file_picker`), cropped
  to a centred square and shrunk to 256×256 JPEG before upload. Shown as a
  circle. No picture → a circle with the username's first letter on a
  colour from the username. "Remove picture" too. *(Claude's call: centre
  crop, no crop UI.)*
- **Delete account:** behind a confirmation dialog. The app first deletes
  the user's own pictures (allowed by the storage rules), then calls a
  `security definer` database function that deletes the signed-in user
  from `auth.users` (the profile goes with it by cascade), then signs out.
  No service-role key anywhere. *(Claude's calls; app stores expect
  deletion.)*

## Where it shows

- **Settings → Account**, at the top of Settings: signed out → "Sign up"
  and "Log in"; signed in → picture, username, email, "Change username",
  "Change picture", "Log out", "Delete account". *(Claude's call.)*
- **Desktop title bar:** a small round avatar (or a person icon with a
  "Log in" tooltip when signed out) in the top bar, to the right of the
  search field and just left of the minimize / maximize / close buttons
  (`lib/ui/shell/title_bar.dart`); it opens Settings → Account. *(The user
  decided the place.)* Where the app runs without its own title bar (the
  search row at the top of the main pane, `_SearchRow` in
  `lib/ui/shell/desktop_shell.dart`), the avatar sits at the right end of
  that row instead. Not in the sidebar.
- Sign-up / log-in screens: a dialog on wide layouts, a full page on
  phones (root navigator, as the bug-report form).

## Data (Supabase)

- `auth.users` — Supabase's own.
- `public.profiles` — `id` (= auth user id, primary key), `username`
  (unique, case-insensitive), `avatar_path` (nullable), `created_at`,
  `updated_at`. Row-level security: anyone signed in can read profiles
  (needed later for listen together); only the owner can insert/update
  their own row; no deletes except through account deletion.
- Storage bucket `avatars` — public read; a user can write only under
  their own folder `<user id>/`.
- Functions: `username_available(name text) returns boolean` (callable
  signed out), `delete_my_account()` (security definer, deletes
  `auth.uid()`'s user), and the sign-up trigger that creates the profile
  from the metadata.

## Platforms and testing

Android, Windows and Linux. The app logic is tested with fakes of the
Supabase client (unit and widget tests). The migrations are checked by the
user applying them to the real project and walking a short checklist in
`docs/manual-test-checklist.md` (sign up, confirm, log in, change username
and picture, log out, reset password, delete). *(Claude's call: no local
Supabase in tests.)*

## Goals

- A friend can create an account, confirm it, log in, and set a username
  and picture in a couple of minutes, on Android, Windows and Linux.
- Being signed out, offline or on a paused Supabase project never breaks
  the rest of the app.

## Non-goals

- Syncing anything (step 2), devices list / remote control (step 3),
  listen together (step 4).
- Passkeys, Google or other social sign-in.
- Changing email or password from inside the app (password reset covers
  the forgotten case). *(Claude's call; can come later.)*

## Anti-goals

- Secrets in the repo (only the public URL and publishable key go in).
- Any other user's email visible to a user.
- An account required to play music.

## Left to the builder

- Package (`supabase_flutter`), widget layout, how the keyring storage
  adapter is written, migration file names, the avatar colour palette.
