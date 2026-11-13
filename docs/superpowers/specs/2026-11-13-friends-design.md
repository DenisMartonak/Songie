# Friends (SON-34)

Part 2 of 3, split from SON-21. Friend activity (what they play now, their
top 10, listening together) is SON-35 and builds on this.

## Intent

Songies users can find each other by name and become friends, so later
(SON-35) friends can see and join each other's listening. This part covers:

- finding people;
- requests;
- the friends list.

## Decisions (user's)

- **Mutual friends.** One person sends a request, the other accepts, and
  then both are friends. There is no one-way follow.
- **Finding people.** A "Songies Users" tab in search finds people by name.
- **Friends page.** A dedicated page for friends.
- **Noticing requests (A).** A dot on your picture in the header and on
  the Friends row, with requests waiting on the Friends page. The app
  checks when it opens and every so often. There is no live push and no
  pop-up.
- **How (approach 1, picked).** A `friendships` table the app may read but
  not write. Every change goes through security-definer server functions,
  as rooms and sync already do.

## Approaches considered

- **1. Table plus server functions (picked).** The rules live in one place
  on the server, and a modified app can't create odd rows.
- **2. Table with row policies, written directly by the app.** It needs
  less SQL. But the rules would be split between policies and app code,
  and any policy gap would let a client, say, accept on someone's behalf.

## Constraints

- **Migration.** A new file,
  `supabase/migrations/20261114120000_friends.sql`, that the user applies.
  Add a matching section to `docs/supabase.md`, as for the earlier
  migrations.
- **Profiles.** They are already readable by every signed-in user, so the
  user search needs no new rule.
- **Signed out:** no friends features. The search tab says "Log in to find
  friends".

## Design

### Server

- **Table.** `public.friendships(requester uuid, addressee uuid, status
  text check in ('pending','accepted'), created_at, accepted_at)`.
  - Primary key `(requester, addressee)`.
  - It checks `requester <> addressee`.
  - Both columns reference `auth.users` with `on delete cascade`, so
    deleting an account removes its friendships.
  - A unique index on the unordered pair
    `(least(requester, addressee), greatest(...))` keeps one row per pair.
- **Reading.** RLS lets a user select only rows where they are the
  requester or the addressee. There are no insert, update or delete
  grants.
- **Functions** (security definer, `auth.uid()` as the caller, granted to
  `authenticated`):
  - `send_friend_request(other uuid) returns text`. The result is the new
    status:
    - `pending` for a new request;
    - `accepted` if `other` had already asked you;
    - no change if a row already exists.
    - It raises on a request to yourself or to an unknown user.
  - `accept_friend_request(other uuid)`: only the addressee of a pending
    row can accept.
  - `remove_friend(other uuid)`: deletes the pair's row whatever its state.
    That covers declining, cancelling and unfriending.
- **Search** reads `profiles` directly:
  - `username ilike '<query>%'`, case-insensitive;
  - excluding yourself, ordered by username, limit 20.
  - The app escapes `%` and `_` in the query.

### App

- **`FriendsBackend`.** It wraps the RPCs and selects, and is faked in
  tests, like `RoomBackend`.
- **`FriendsService`.** It exposes `friends`, `incoming` and `outgoing`,
  each a list of `{userId, username, avatarUrl}`.
  - It refreshes on sign-in, on app start, every 5 minutes while signed
    in, and when the Friends page opens.
  - After any action it refreshes.
  - `incomingCount` drives the dot.
- **Search tab.** "Songies Users" goes after Playlists in the tab row.
  - Rows show the picture, the name and a state button:
    - Add friend (no relation);
    - Requested, which cancels on tap;
    - Accept (they asked you);
    - Friends (no action).
  - With fewer than 2 letters, the tab says "Type at least 2 letters".
  - With nobody found: "No Songies users found".
- **Friends page.** `/profile/friends`, opened from a "Friends" row on the
  profile page. The row shows the friend count and the dot.
  - Sections, each shown only when not empty:
    - Requests (Accept / Decline);
    - Sent (Cancel);
    - Friends.
  - An empty state invites you to find people in search.
- **Friend page.** `/profile/friends/:userId`: their picture, name and a
  Remove friend button that asks first. SON-35 adds their activity here.
- **Dot.** A small accent dot on `AccountButton` (header and title bar) and
  on the Friends row while `incomingCount > 0`.

## Non-goals

No blocking, limits, live notifications, friend activity or listening
together (SON-35).

## Left to the builder

- Exact layout of the rows.
- The polling timer's home (a provider tied to the account state).
- SQL details beyond the rules above.
