# User profile page (SON-21)

Part 1 of 3. Friends are SON-34, and friend activity is SON-35.

## Intent

Your own profile page, one tap from Home: your picture, your name, your
listening stats and everything about your account. Settings is left with
app settings only. Editing your picture and name gets easier.

## Decisions (user's)

- **Content.** The profile page holds:
  - the picture, name and email;
  - your listening stats;
  - at the bottom, the sync status with Sync now, Log out and Delete
    account.
- **Settings.** The Account section is removed from Settings entirely
  (option A).
- **Your picture in the header.** It sits next to Settings in the Home
  menu, and tapping it opens your profile.
- **Picture.** Tapping it enlarges it, with Change picture and Remove
  picture underneath.
- **Name.** Tapping it lets you change it.
- **How (approach 1, picked).** A new Profile page that reuses the stats
  content. Home's listening card keeps opening the stats-only page.

## Approaches considered

- **1. New Profile page reusing the stats content (picked).** The stats
  content is pulled out of `StatsPage` into a shared widget. `/stats`
  stays a focused page of numbers.
- **2. The stats page becomes the profile.** It is a bit less code. But
  the listening card would land on Log out and Delete account, and stats
  would lose their own page.

## Design

- **Route.** `/profile`, a page inside the shell like `/stats`.
- **Entry points.**
  - Phone: an avatar button in the Home header, just before Settings.
  - Desktop: the title bar's `AccountButton` opens `/profile` instead of
    `/settings`.
  - Signed out, the button shows the person icon and opens the
    Log in / Sign up screen (`showAuthScreen`). There is no profile page
    when signed out.
- **Profile page, top to bottom:**
  1. **Header.** A large avatar, then the username, then the email
     (muted).
  2. **Stats.** The shared stats content: period picker, minutes, chart,
     top artists and top songs.
  3. **Account.** The sync status line with Sync now, then Log out, then
     Delete account (in the error colour).
- **Picture viewer.** Tapping the avatar opens a dialog with the picture
  at about 240 px. Underneath are Change picture and Remove picture;
  Remove shows only when there is a picture. These use the existing
  picker, upload and remove flows from `AccountSection`.
- **Inline name edit.** Tapping the username swaps it for a text field
  with the current name. Enter or a check button saves; Esc or focus loss
  cancels. It uses the same validation and errors as today's Change
  username dialog. Success shows the existing island.
- **Settings.** The Account section and its heading are removed.
  - Anything in the app that links to "Settings → Account" now points at
    `/profile`.
  - If signed out, it opens the auth screen instead.

## Non-goals

No other users' profiles, no friends and no privacy switches. Those
belong to SON-34 and SON-35.

## Left to the builder

Exact spacing and sizes in the header, and how the shared stats widget is
cut out of `StatsPage`.
