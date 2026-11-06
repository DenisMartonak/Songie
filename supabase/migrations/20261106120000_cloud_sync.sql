-- Songies cloud sync, step 2: the synced rows of each account, the push and
-- pull functions, a Realtime Broadcast notice per push, and the private
-- sync-files bucket. Apply once, after 20261105120000_accounts.sql (see
-- docs/supabase.md).

-- Synced rows ------------------------------------------------------------------

-- One row per synced drift row of an account. `data` is the drift row's
-- toJson() (NUL in strings escaped by the app, as jsonb can't hold it); tbl,
-- id, clock, origin_device and deleted repeat its stamp so the server can
-- compare clocks without reading the JSON. fmt is the shape of `data`, the
-- app's row format (kRowFormat in lib/sync/cloud/cloud_remote.dart), so an
-- older app never overwrites a newer-format row. server_seq grows on every
-- insert and update, so a device asks "what changed after the last
-- server_seq I pulled".
create sequence public.sync_rows_server_seq;

create table public.sync_rows (
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  tbl text not null,
  id text not null,
  clock text not null,
  origin_device text not null,
  deleted boolean not null,
  fmt integer not null check (fmt > 0),
  data jsonb not null,
  -- Set by the sync_rows_stamp trigger below.
  server_seq bigint not null,
  updated_at timestamptz default now(),
  primary key (user_id, tbl, id),
  -- The eight SyncTable wire names (lib/sync/sync_row.dart).
  constraint sync_rows_tbl_rule check (tbl in (
    'tracks', 'playlists', 'playlist_entries', 'yt_seen',
    'themes', 'fonts', 'lyrics', 'listens'
  )),
  -- Hlc.pack() in lib/core/hlc.dart: <13-digit wall ms>-<5-digit counter>-<device id>.
  constraint sync_rows_clock_rule check (clock ~ '^[0-9]{13}-[0-9]{5}-.+$')
);

alter sequence public.sync_rows_server_seq owned by public.sync_rows.server_seq;

create index sync_rows_user_seq on public.sync_rows (user_id, server_seq);

-- A fresh server_seq (and updated_at) on every insert and update, whoever
-- writes the row.
--
-- Every write to sync_rows must go through push_rows (or take the same
-- per-account advisory lock, see push_rows). A write outside that lock can
-- take a server_seq and commit after a later one has been pulled, and a
-- device whose watermark is already past it never sees that row.
create function public.sync_rows_stamp()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.server_seq := nextval('public.sync_rows_server_seq');
  new.updated_at := now();
  return new;
end;
$$;

revoke all on function public.sync_rows_stamp() from public, anon, authenticated;

create trigger sync_rows_stamp
  before insert or update on public.sync_rows
  for each row execute function public.sync_rows_stamp();

alter table public.sync_rows enable row level security;

-- Read only your own rows (pull_rows goes through this).
create policy "Users read their own sync rows"
  on public.sync_rows for select
  to authenticated
  using (user_id = (select auth.uid()));

-- No insert, update or delete policy and no write grants: every write goes
-- through push_rows. Rows go only with their account (on delete cascade).
revoke all on table public.sync_rows from anon, authenticated;
grant select on table public.sync_rows to authenticated;
revoke all on sequence public.sync_rows_server_seq from anon, authenticated;

-- Push -------------------------------------------------------------------------

-- Upserts up to 500 rows for the caller. Each element of `rows` is
-- {tbl, id, clock, origin_device, deleted, fmt, data}; a user_id in it is
-- ignored (the caller's auth.uid() is always used). A row is written only
-- when it is new or its clock is newer than the stored one, so devices can't
-- overwrite each other out of order, and never over a stored row of a newer
-- fmt (an older app would drop the fields it doesn't know; that app sees the
-- newer row when it pulls, asks for an update, and after it pushes its rows
-- again). Returns how many rows were written.
--
-- Clocks compare as text in the "C" (byte) collation: the packed HLC has a
-- fixed-width zero-padded wall time and counter, then the device id, so byte
-- order equals Hlc.compareTo (wall, counter, device id by code unit, for the
-- ASCII device ids Songies makes). The database's default collation could
-- order the device-id part differently, hence the explicit collation.
--
-- Pushes of one account run one at a time (a transaction-level advisory
-- lock), so server_seq is handed out in commit order per account and a pull
-- never skips a row that commits later with a smaller server_seq.
--
-- Also rejected: a row whose data is over 256 KB as JSON text (a long synced
-- lyrics row is a few tens of KB), and a clock whose wall time is more than
-- a day ahead of the server's (a device with a far-future clock would
-- otherwise win every row it touches for good).
create function public.push_rows(rows jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  written integer;
begin
  if uid is null then
    raise exception 'not signed in';
  end if;
  if rows is null or jsonb_typeof(rows) <> 'array' then
    raise exception 'rows must be a JSON array';
  end if;
  if jsonb_array_length(rows) > 500 then
    raise exception 'at most 500 rows per push';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(rows) as e (r)
    where jsonb_typeof(e.r) <> 'object'
      or jsonb_typeof(e.r -> 'tbl') is distinct from 'string'
      or e.r ->> 'tbl' not in (
        'tracks', 'playlists', 'playlist_entries', 'yt_seen',
        'themes', 'fonts', 'lyrics', 'listens'
      )
      or jsonb_typeof(e.r -> 'id') is distinct from 'string'
      or e.r ->> 'id' = ''
      or jsonb_typeof(e.r -> 'clock') is distinct from 'string'
      or e.r ->> 'clock' !~ '^[0-9]{13}-[0-9]{5}-.+$'
      or jsonb_typeof(e.r -> 'origin_device') is distinct from 'string'
      or jsonb_typeof(e.r -> 'deleted') is distinct from 'boolean'
      or jsonb_typeof(e.r -> 'fmt') is distinct from 'number'
      or e.r ->> 'fmt' !~ '^[1-9][0-9]{0,8}$'
      or jsonb_typeof(e.r -> 'data') is distinct from 'object'
  ) then
    raise exception 'invalid row in push (tbl, id, clock, origin_device, deleted, fmt or data)';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(rows) as e (r)
    where octet_length((e.r -> 'data')::text) > 262144
  ) then
    raise exception 'row data over 256 KB';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(rows) as e (r)
    where left(e.r ->> 'clock', 13)::bigint
      > (extract(epoch from now()) * 1000)::bigint + 86400000
  ) then
    raise exception 'clock more than a day in the future';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('sync_rows:' || uid::text, 0));

  insert into public.sync_rows as s
    (user_id, tbl, id, clock, origin_device, deleted, fmt, data)
  -- The same row twice in one push: keep the newest clock (an upsert can't
  -- touch one row twice).
  select distinct on (e.r ->> 'tbl', e.r ->> 'id')
    uid,
    e.r ->> 'tbl',
    e.r ->> 'id',
    e.r ->> 'clock',
    e.r ->> 'origin_device',
    (e.r -> 'deleted')::boolean,
    (e.r ->> 'fmt')::integer,
    e.r -> 'data'
  from jsonb_array_elements(rows) as e (r)
  order by e.r ->> 'tbl', e.r ->> 'id', (e.r ->> 'clock') collate "C" desc
  on conflict (user_id, tbl, id) do update
    set clock = excluded.clock,
        origin_device = excluded.origin_device,
        deleted = excluded.deleted,
        fmt = excluded.fmt,
        data = excluded.data
    where excluded.clock collate "C" > s.clock collate "C"
      and excluded.fmt >= s.fmt;

  get diagnostics written = row_count;
  return written;
end;
$$;

revoke all on function public.push_rows(jsonb) from public, anon, authenticated;
grant execute on function public.push_rows(jsonb) to authenticated;

-- Pull -------------------------------------------------------------------------

-- The caller's rows with server_seq > after, oldest first, at most `max`
-- (capped at 500). Runs as the caller, so row-level security filters too.
create function public.pull_rows(after bigint, max integer default 500)
returns setof public.sync_rows
language sql
stable
security invoker
set search_path = ''
as $$
  select s.*
  from public.sync_rows s
  where s.user_id = (select auth.uid())
    and s.server_seq > pull_rows.after
  order by s.server_seq
  limit least(greatest(coalesce(pull_rows.max, 500), 0), 500);
$$;

revoke all on function public.pull_rows(bigint, integer) from public, anon, authenticated;
grant execute on function public.pull_rows(bigint, integer) to authenticated;

-- Realtime -----------------------------------------------------------------------

-- sync_rows is NOT in the supabase_realtime publication: postgres_changes
-- doesn't apply RLS to DELETE events, so an account deletion's cascade would
-- tell every subscriber the deleted rows' keys. Instead, each write statement
-- sends a Broadcast message on the PRIVATE topic sync:<user id> carrying only
-- the new highest server_seq; a device treats any message as "pull now".
--
-- One message per statement and account. An upsert that both inserts and
-- updates rows fires both statement triggers, so a push can send two.
create function public.sync_rows_notify()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
begin
  for r in
    select n.user_id, max(n.server_seq) as server_seq
    from new_rows n
    group by n.user_id
  loop
    perform realtime.send(
      jsonb_build_object('server_seq', r.server_seq),
      'changed',
      'sync:' || r.user_id::text,
      true
    );
  end loop;
  return null;
end;
$$;

revoke all on function public.sync_rows_notify() from public, anon, authenticated;

-- Transition tables allow only one event per trigger, hence two triggers.
create trigger sync_rows_notify_insert
  after insert on public.sync_rows
  referencing new table as new_rows
  for each statement execute function public.sync_rows_notify();

create trigger sync_rows_notify_update
  after update on public.sync_rows
  referencing new table as new_rows
  for each statement execute function public.sync_rows_notify();

-- Who may join a private Broadcast topic: Realtime checks these policies on
-- realtime.messages with realtime.topic() set to the topic. A signed-in user
-- may receive only on sync:<their id>. There is no insert policy, so no
-- client can send on these topics (only the trigger above, in the database).
create policy "sync: users receive their own sync topic"
  on realtime.messages for select
  to authenticated
  using (
    realtime.messages.extension = 'broadcast'
    and (select realtime.topic()) = 'sync:' || (select auth.uid())::text
    and realtime.messages.topic = (select realtime.topic())
  );

-- sync-files bucket ----------------------------------------------------------------

-- Private. Files are <user id>/<kind>/<hash>.<ext>, kind = font | art.
-- At most 10 MB a file, fonts and images only; uploads must set one of these
-- content types.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'sync-files', 'sync-files', false, 10485760,
  array[
    'font/ttf', 'font/otf', 'application/font-sfnt', 'application/x-font-ttf',
    'application/x-font-otf', 'application/vnd.ms-opentype',
    'image/jpeg', 'image/png', 'image/webp'
  ]
)
on conflict (id) do nothing;

-- Everything only inside the caller's own folder. Select is needed too:
-- Storage's update and delete read the row first. Uploads also need the
-- caller's profile, which goes with the account (on delete cascade): a
-- device whose token outlives a deleted account (tokens last up to an hour)
-- can't put files back into the folder the app emptied.
create policy "sync-files: users read their own folder"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'sync-files'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "sync-files: users upload to their own folder"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'sync-files'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and exists (select 1 from public.profiles p where p.id = (select auth.uid()))
  );

create policy "sync-files: users update their own files"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'sync-files'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'sync-files'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and exists (select 1 from public.profiles p where p.id = (select auth.uid()))
  );

create policy "sync-files: users delete their own files"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'sync-files'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- delete_my_account (20261105120000_accounts.sql) is unchanged: deleting the
-- auth user removes its sync_rows by cascade. The app deletes the caller's
-- sync-files/<user id>/ files first (built with the file sync, later).
