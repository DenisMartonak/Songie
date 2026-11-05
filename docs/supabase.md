# Supabase setup

Songies accounts run on the Supabase project `dxxbowrmuxtzwrhmulnx` (free tier). Do these steps once. The database part is in the repo (`supabase/migrations/`); the rest are dashboard settings that can't live in the repo.

## 1. Apply the database migration

Either with the Supabase CLI (logged in as you):

```
npx supabase login
npx supabase link --project-ref dxxbowrmuxtzwrhmulnx
npx supabase db push
```

Or by hand: open the dashboard, SQL Editor, New query, paste the whole of `supabase/migrations/20261105120000_accounts.sql`, and press Run. It should finish with "Success. No rows returned".

Either way it creates the `profiles` table, the sign-up trigger, the `username_available` and `delete_my_account` functions, and the public `avatars` storage bucket with its rules. Run it only once; a second run fails because the table already exists. Later migrations go in the same folder and are pushed the same way.

## 2. Email sign-in settings

In the dashboard open Authentication, Sign In / Providers, Email:

1. Email provider: on.
2. Confirm email: on.
3. Minimum password length: 8.
4. Email OTP expiration: 3600 seconds (1 hour).
5. Email OTP length: 6.
6. Save.

## 3. Email templates (codes instead of links)

Songies asks for a 6-digit code instead of opening a link, because links can't reliably open the app on Linux and Windows. In Authentication, Emails, Templates, replace two templates.

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

## 4. Things to know

- Email limit: Supabase's built-in sender only sends a few emails an hour, from Supabase's own address. That's fine for you and a few friends. If sign-ups or code emails stop arriving, wait an hour, or set up a custom SMTP sender later (Authentication, Emails, SMTP Settings).
- Pausing: a free project pauses after 7 days without activity. Songies keeps working signed out while it's paused. Restore it from the dashboard (the project page shows a Restore button).
- The app's keys: the project URL and the publishable key are in the dashboard under Project Settings, API Keys (and Data API for the URL). They are public by design and live in `lib/account/supabase_config.dart`.
- Never put the service-role key (or the secret key) in the app or in the repo. It bypasses every rule above. Songies doesn't need it: account deletion goes through `delete_my_account`.
