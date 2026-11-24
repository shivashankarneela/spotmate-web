alter table public.user_profiles
  add column username text,
  add constraint user_profiles_username_format
    check (username ~ '^[A-Za-z0-9_-]+$');

create unique index user_profiles_username_unique
  on public.user_profiles (lower(username));

create table private.city_presence (
  user_id uuid not null references public.user_profiles(id) on delete cascade,
  session_id uuid not null,
  room_id uuid not null references public.hotspots(id) on delete cascade,
  seen_at timestamptz not null,
  primary key (user_id, session_id, room_id)
);

create function public.set_city_presence(p_room uuid, p_present boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  sid uuid := (auth.jwt()->>'session_id')::uuid;
begin
  if uid is null or sid is null then return; end if;
  if not p_present then
    delete from private.city_presence
    where user_id = uid and session_id = sid and room_id = p_room;
    return;
  end if;
  if exists (
    select 1 from public.hotspots h where h.id = p_room
      and h.is_city_chat and h.status = 'approved'
  ) and private.is_active_hotspot_member(p_room) then
    insert into private.city_presence (user_id, session_id, room_id, seen_at)
    values (uid, sid, p_room, clock_timestamp())
    on conflict (user_id, session_id, room_id)
    do update set seen_at = excluded.seen_at;
    delete from private.city_presence
    where user_id = uid and seen_at < now() - interval '1 day';
  end if;
end;
$$;

create function public.spotmate_friends()
returns table (friend_id uuid, connection_id uuid, name text, username text, city text)
language sql stable security definer set search_path = '' as $$
  with friends as (
    select distinct on (p.id) p.id, c.id as connection_id, p.name, p.username
    from public.connections c
    join public.user_profiles p
      on p.id = case when c.user1_id = auth.uid() then c.user2_id else c.user1_id end
    where auth.uid() in (c.user1_id, c.user2_id)
      and p.is_active
      and not exists (
        select 1 from public.user_blocks b
        where (b.blocker_id = auth.uid() and b.blocked_id = p.id)
           or (b.blocker_id = p.id and b.blocked_id = auth.uid())
      )
    order by p.id, c.id
  )
  select f.id, f.connection_id, f.name, f.username, room.city
  from friends f
  left join lateral (
    select city.name as city
    from private.city_presence p
    join public.hotspots h on h.id = p.room_id and h.is_city_chat and h.status = 'approved'
    join public.hotspot_members m on m.user_id = p.user_id and m.hotspot_id = h.id
      and m.status = 'active' and m.expires_at > now()
    join public.cities city on city.id = h.city_id
    where p.user_id = f.id and p.seen_at > now() - interval '90 seconds'
    order by p.seen_at desc, p.room_id
    limit 1
  ) room on true
  order by lower(f.name), f.id;
$$;

revoke all on function public.set_city_presence(uuid, boolean), public.spotmate_friends()
  from public, anon;
grant execute on function public.set_city_presence(uuid, boolean), public.spotmate_friends()
  to authenticated;
