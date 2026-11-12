-- Saved artists sync (SON-10): sync_rows accepts the ninth table,
-- 'saved_artists'. Both places that list the table names change: the
-- sync_rows_tbl_rule check and push_rows. pull_rows and the Realtime notice
-- name no tables, so they stay as they are.
--
-- Apply this before releasing the app version that syncs saved artists: until
-- then push_rows refuses those rows (invalid row), and the app skips refused
-- rows for good.

alter table public.sync_rows drop constraint if exists sync_rows_tbl_rule;
alter table public.sync_rows add constraint sync_rows_tbl_rule check (tbl in (
  'tracks', 'playlists', 'playlist_entries', 'yt_seen',
  'themes', 'fonts', 'lyrics', 'listens', 'saved_artists'
));

-- push_rows, unchanged except for the added table name. The grants below are
-- the same as before; create or replace keeps them, and they are repeated to
-- be safe.
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
create or replace function public.push_rows(rows jsonb)
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
        'themes', 'fonts', 'lyrics', 'listens', 'saved_artists'
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
