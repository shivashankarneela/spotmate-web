create table private.spotmate_ids (
  user_id uuid primary key references public.user_profiles(id) on delete cascade,
  spotmate_id text not null
);

create unique index spotmate_ids_case_insensitive
  on private.spotmate_ids (lower(spotmate_id));

insert into private.spotmate_ids (user_id, spotmate_id)
select id, spotmate_id from public.user_profiles where spotmate_id is not null;

update public.user_profiles set spotmate_id = null where spotmate_id is not null;

create sequence private.spotmate_id_sequence
  as integer start with 100000 maxvalue 999999;

create function private.assign_spotmate_id(p_user uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  while not exists (select 1 from private.spotmate_ids where user_id = p_user) loop
    insert into private.spotmate_ids (user_id, spotmate_id)
    values (p_user, 'SM-' || nextval('private.spotmate_id_sequence'))
    on conflict do nothing;
  end loop;
end;
$$;

select private.assign_spotmate_id(p.id)
from public.user_profiles p
where not exists (select 1 from private.spotmate_ids ids where ids.user_id = p.id);

-- Keep the legacy field empty, including when older clients write to it.
create function private.mask_public_spotmate_id()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.spotmate_id := null;
  return new;
end;
$$;

alter table public.user_profiles add constraint user_profiles_spotmate_id_private
  check (spotmate_id is null);

create trigger mask_public_spotmate_id before insert or update of spotmate_id
on public.user_profiles for each row execute function private.mask_public_spotmate_id();

create function private.assign_new_profile_spotmate_id()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform private.assign_spotmate_id(new.id);
  return new;
end;
$$;

create trigger assign_new_profile_spotmate_id after insert on public.user_profiles
for each row execute function private.assign_new_profile_spotmate_id();

revoke all on function private.assign_spotmate_id(uuid),
  private.assign_new_profile_spotmate_id() from public, anon, authenticated;

create function public.visible_spotmate_ids(p_users uuid[])
returns table(user_id uuid, spotmate_id text)
language sql stable security definer set search_path = '' as $$
  select ids.user_id, ids.spotmate_id
  from private.spotmate_ids ids
  where ids.user_id = any(p_users) and (
    ids.user_id = auth.uid() or (
      exists (
        select 1 from public.connections c
        where (c.user1_id = auth.uid() and c.user2_id = ids.user_id)
           or (c.user2_id = auth.uid() and c.user1_id = ids.user_id)
      )
      and not exists (
        select 1 from public.user_blocks b
        where (b.blocker_id = auth.uid() and b.blocked_id = ids.user_id)
           or (b.blocked_id = auth.uid() and b.blocker_id = ids.user_id)
      )
    )
  );
$$;

create or replace function public.find_spotmate_people(p_query text)
returns table(id uuid,name text,spotmate_id text,profile_photo text,avatar_type text,avatar_emoticon text)
language sql stable security invoker set search_path = '' as $$
  select p.id, p.name, null::text, p.profile_photo, p.avatar_type, p.avatar_emoticon
  from public.user_profiles p
  where auth.uid() is not null and p.id <> auth.uid() and p.is_active
    and length(trim(p_query)) between 2 and 64
    and (strpos(lower(p.name), lower(trim(p_query))) > 0
      or lower(p.username) = lower(trim(p_query)))
    and not exists (
      select 1 from public.user_blocks b
      where (b.blocker_id = auth.uid() and b.blocked_id = p.id)
         or (b.blocked_id = auth.uid() and b.blocker_id = p.id)
    )
  order by p.name, p.id
  limit 30;
$$;

create function public.connected_spotmate_player(p_spotmate_id text)
returns uuid language sql stable security definer set search_path = '' as $$
  select ids.user_id
  from private.spotmate_ids ids
  join public.user_profiles p on p.id = ids.user_id and p.is_active
  where lower(ids.spotmate_id) = lower(trim(p_spotmate_id))
    and exists (select 1 from public.visible_spotmate_ids(array[ids.user_id]))
    and ids.user_id <> auth.uid();
$$;

revoke all on function public.visible_spotmate_ids(uuid[]), public.connected_spotmate_player(text)
  from public, anon;
grant execute on function public.visible_spotmate_ids(uuid[]), public.connected_spotmate_player(text)
  to authenticated;

revoke execute on function public.remove_hotspot_message(uuid)
  from public, anon, authenticated;
