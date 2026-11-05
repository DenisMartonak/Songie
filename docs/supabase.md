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

Or by hand: open the dashboard, SQL Editor, New query, paste the whole of `supabase/migrations/20261105120000_accounts.sql`, and press Run. It should finish with "Success. No rows returned".

Either way it creates the `profiles` table, the sign-up trigger, the `username_available` and `delete_my_account` functions, and the public `avatars` storage bucket with its rules. Run it only once; a second run fails because the table already exists. Later migrations go in the same folder and are pushed the same way.

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
- Pausing: a free project pauses after 7 days without activity. Songies keeps working signed out while it's paused. Restore it from the dashboard (the project page shows a Restore button).
- The app's keys: the project URL is on the dashboard's Connect button (and under Project Settings, Data API); the publishable key is under Project Settings, API Keys. Both are public by design and live in `lib/account/supabase_config.dart`.
- Never put the service-role key (or the secret key) in the app or in the repo. It bypasses every rule above. Songies doesn't need it: account deletion goes through `delete_my_account`.
- `supabase/config.toml` only configures a local test database (`npx supabase@3 db start`). Its auth settings match the steps above; don't run `supabase config push` without checking it, because that copies them to the real project.
