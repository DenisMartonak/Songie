-- Playlist sharing: an account shares a playlist by link; anyone signed in
-- with the link can follow it (their copy updates from it) or copy it. Apply
-- once, after 20261115120000_friend_activity.sql (see docs/supabase.md).
--
-- The owner's device publishes a snapshot of the playlist's songs under a
-- code; followers' devices fetch it. Only the functions below touch the
-- table: the code in the link is what lets someone read a share.

-- Shared playlists -----------------------------------------------------------------

-- code: 12 letters from an alphabet without 0, O, 1, I and L (as room codes).
-- songs: [{"videoId", "title", "artist", "album"?, "durationMs"?, "artUrl"?}].
-- Stopping a share deletes its row; rows go with the owner's account.
create table public.shared_playlists (
  code text primary key,
  owner uuid not null references auth.users (id) on delete cascade,
  name text not null,
  songs jsonb not null,
  updated_at timestamptz not null default now(),
  constraint shared_playlists_code_rule
    check (code ~ '^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{12}$')
);

create index shared_playlists_owner on public.shared_playlists (owner);

alter table public.shared_playlists enable row level security;
revoke all on table public.shared_playlists from anon, authenticated;

-- Fails with too_large when a snapshot is over 512 kB (about 2,500 songs).
create function public.check_shared_songs(p_name text, p_songs jsonb)
returns void
language plpgsql
immutable
set search_path = ''
as $$
begin
  if jsonb_typeof(p_songs) is distinct from 'array' then
    raise exception 'bad_songs';
  end if;
  if octet_length(p_songs::text) > 524288 or length(coalesce(p_name, '')) > 200 then
    raise exception 'too_large';
  end if;
end;
$$;

revoke all on function public.check_shared_songs(text, jsonb) from public, anon, authenticated;

-- Shares a playlist: stores the snapshot under a fresh code and returns it.
create function public.share_playlist(p_name text, p_songs jsonb)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  new_code text;
  done boolean := false;
  b int;
begin
  if me is null then
    raise exception 'not_signed_in';
  end if;
  perform public.check_shared_songs(p_name, p_songs);

  for attempt in 1..10 loop
    -- As open_room: a byte of 248 or more is skipped, so the rest map evenly
    -- onto the 31 letters.
    new_code := '';
    while length(new_code) < 12 loop
      for b in select get_byte(extensions.gen_random_bytes(24), i) from generate_series(0, 23) i loop
        if b < 248 and length(new_code) < 12 then
          new_code := new_code || substr(alphabet, 1 + b % 31, 1);
        end if;
      end loop;
    end loop;
    begin
      insert into public.shared_playlists (code, owner, name, songs)
        values (new_code, me, coalesce(p_name, ''), p_songs);
      done := true;
      exit;
    exception when unique_violation then
      done := false;
    end;
  end loop;
  if not done then
    raise exception 'no_free_code';
  end if;
  return new_code;
end;
$$;

-- Replaces a share's name and songs; only its owner may.
create function public.update_shared_playlist(p_code text, p_name text, p_songs jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
begin
  if me is null then
    raise exception 'not_signed_in';
  end if;
  perform public.check_shared_songs(p_name, p_songs);
  update public.shared_playlists
    set name = coalesce(p_name, ''), songs = p_songs, updated_at = now()
    where code = p_code and owner = me;
  if not found then
    raise exception 'not_owner';
  end if;
end;
$$;

-- Stops a share: the link no longer works and followers keep their copy.
-- Only its owner may; an unknown code is fine (already stopped).
create function public.stop_sharing_playlist(p_code text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
begin
  if me is null then
    raise exception 'not_signed_in';
  end if;
  if exists (
    select 1 from public.shared_playlists s
    where s.code = p_code and s.owner <> me
  ) then
    raise exception 'not_owner';
  end if;
  delete from public.shared_playlists where code = p_code and owner = me;
end;
$$;

-- A share as anyone with its code sees it: no rows when it's unknown or
-- stopped. owner_name is the owner's username; is_mine says whether the caller
-- owns it.
create function public.get_shared_playlist(p_code text)
returns table (
  name text,
  owner_name text,
  songs jsonb,
  updated_at timestamptz,
  is_mine boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select s.name, coalesce(p.username, ''), s.songs, s.updated_at,
    s.owner = (select auth.uid())
  from public.shared_playlists s
  left join public.profiles p on p.id = s.owner
  where s.code = p_code and (select auth.uid()) is not null;
$$;

revoke all on function public.share_playlist(text, jsonb) from public, anon, authenticated;
revoke all on function public.update_shared_playlist(text, text, jsonb) from public, anon, authenticated;
revoke all on function public.stop_sharing_playlist(text) from public, anon, authenticated;
revoke all on function public.get_shared_playlist(text) from public, anon, authenticated;
grant execute on function public.share_playlist(text, jsonb) to authenticated;
grant execute on function public.update_shared_playlist(text, text, jsonb) to authenticated;
grant execute on function public.stop_sharing_playlist(text) to authenticated;
grant execute on function public.get_shared_playlist(text) to authenticated;
