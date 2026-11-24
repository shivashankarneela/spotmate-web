create table private.verified_profile_emails (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  verified_at timestamptz not null default now()
);

create function public.spotmate_record_email_verification()
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  address text;
begin
  select lower(u.email) into address from auth.users u where u.id = uid;
  if address is null then return false; end if;
  if exists (
    select 1 from jsonb_array_elements(coalesce(auth.jwt()->'amr', '[]'::jsonb)) as method
    where method->>'method' in ('otp', 'magiclink')
      and coalesce(method->>'timestamp', '0')::bigint >= extract(epoch from now() - interval '1 hour')
      and lower(auth.jwt()->>'email') = address
  ) then
    insert into private.verified_profile_emails (user_id, email) values (uid, address)
      on conflict (user_id) do update set email = excluded.email, verified_at = now()
      where private.verified_profile_emails.email <> excluded.email;
  end if;
  return exists (
    select 1 from private.verified_profile_emails v where v.user_id = uid and v.email = address
  );
end;
$$;
revoke all on function public.spotmate_record_email_verification() from public, anon;
grant execute on function public.spotmate_record_email_verification() to authenticated;

alter table public.profile_gallery_photos add column for_matchmaker boolean not null default false;
create unique index profile_one_matchmaker_photo on public.profile_gallery_photos(user_id)
  where for_matchmaker;

update public.profile_gallery_photos set for_matchmaker = true
where object_path in (
  select distinct on (user_id) object_path
  from public.profile_gallery_photos order by user_id, created_at, object_path
);

revoke insert on public.profile_gallery_photos from authenticated;
grant insert (user_id, object_path) on public.profile_gallery_photos to authenticated;

create function private.maintain_matchmaker_photo()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  owner_id uuid := case when tg_op = 'INSERT' then new.user_id else old.user_id end;
begin
  perform pg_advisory_xact_lock(hashtextextended('matchmaker-photo:' || owner_id::text, 0));
  if tg_op = 'INSERT' then
    new.for_matchmaker := not exists (
      select 1 from public.profile_gallery_photos where user_id = owner_id and for_matchmaker
    );
    return new;
  end if;
  if old.for_matchmaker then
    update public.profile_gallery_photos set for_matchmaker = true
    where object_path = (
      select object_path from public.profile_gallery_photos
      where user_id = owner_id order by created_at, object_path limit 1
    );
    if not found then
      delete from private.regional_matchmaker_sessions where user_id = owner_id;
    end if;
  end if;
  return old;
end;
$$;

create trigger select_first_matchmaker_photo before insert on public.profile_gallery_photos
for each row execute function private.maintain_matchmaker_photo();
create trigger replace_deleted_matchmaker_photo after delete on public.profile_gallery_photos
for each row execute function private.maintain_matchmaker_photo();

create function public.select_matchmaker_photo(p_path text)
returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'Sign in required'; end if;
  perform pg_advisory_xact_lock(hashtextextended('matchmaker-photo:' || uid::text, 0));
  if not exists (select 1 from public.profile_gallery_photos p
      join storage.objects o on o.bucket_id = 'my-photos' and o.name = p.object_path
      where p.user_id = uid and p.object_path = p_path)
  then raise exception 'Photo unavailable'; end if;
  update public.profile_gallery_photos set for_matchmaker = false
    where user_id = uid and for_matchmaker and object_path <> p_path;
  update public.profile_gallery_photos set for_matchmaker = true
    where user_id = uid and object_path = p_path and not for_matchmaker;
end;
$$;
revoke all on function public.select_matchmaker_photo(text) from public, anon;
grant execute on function public.select_matchmaker_photo(text) to authenticated;

create or replace function private.regional_matchmaker_eligible(p_user uuid)
returns boolean language sql stable set search_path = '' as $$
  select exists (
    select 1 from public.user_profiles p
    join public.profile_gallery_photos g on g.user_id = p.id and g.for_matchmaker
    join storage.objects o on o.bucket_id = 'my-photos' and o.name = g.object_path
    where p.id = p_user and p.is_active and p.city_id is not null
      and p.date_of_birth <= (current_date - interval '18 years')::date
  );
$$;

create or replace function public.spotmate_regional_matchmaker(p_action text default 'view', p_target uuid default null, p_scope text default null)
returns jsonb language plpgsql security definer set search_path = '' as $body$
declare
  actor uuid := auth.uid();
  actor_city uuid;
  actor_state text;
  available boolean;
  own private.regional_matchmaker_sessions%rowtype;
  peer private.regional_matchmaker_sessions%rowtype;
  suggestions jsonb := '[]'::jsonb;
  connection uuid;
  conversation uuid;
  matched boolean := false;
begin
  if actor is null then raise exception 'Sign in required'; end if;
  if p_action is null or p_action not in ('view','start','stop','connect','pass') then
    raise exception 'Invalid matchmaker action';
  end if;
  if p_action = 'stop' then
    delete from private.regional_matchmaker_sessions where user_id = actor;
    p_action := 'view';
  end if;

  select p.city_id, c.state into actor_city, actor_state
    from public.user_profiles p left join public.cities c on c.id=p.city_id where p.id=actor;
  available := private.regional_matchmaker_eligible(actor);
  if p_action = 'start' then
    perform pg_advisory_xact_lock(hashtextextended('matchmaker-photo:' || actor::text, 0));
    available := private.regional_matchmaker_eligible(actor);
    if not available then raise exception 'An adult profile, city and uploaded photo are required'; end if;
    if p_scope is null or p_scope not in ('city','state','any') then raise exception 'Choose a region'; end if;
    delete from private.regional_matchmaker_sessions where user_id=actor
      and (expires_at<=now() or scope<>p_scope or city_id<>actor_city);
    insert into private.regional_matchmaker_sessions(user_id,city_id,scope,expires_at)
      values(actor,actor_city,p_scope,now()+interval '1 hour') on conflict(user_id) do nothing;
  end if;

  if p_action in ('connect','pass') then
    if p_target is null or p_target = actor then raise exception 'Invalid match candidate'; end if;
    perform pg_advisory_xact_lock(hashtextextended(
      'spotmate-match:'||least(actor,p_target)::text||':'||greatest(actor,p_target)::text,0));
  end if;
  select * into own from private.regional_matchmaker_sessions where user_id = actor
    and city_id = actor_city and available and expires_at > now();

  if own.id is not null then
    select coalesce(jsonb_agg(to_jsonb(q)), '[]'::jsonb) into suggestions
    from (
      select p.id, p.name, p.bio, g.object_path as matchmaker_photo,
        p.avatar_emoticon, pc.name as city_name, pc.state as state_name
      from private.regional_matchmaker_sessions s
      join public.user_profiles p on p.id = s.user_id
      join public.profile_gallery_photos g on g.user_id = p.id and g.for_matchmaker
      join public.user_profiles a on a.id = actor
      join public.cities pc on pc.id = p.city_id and pc.id = s.city_id
      where s.expires_at > now() and s.user_id <> actor
        and private.regional_matchmaker_eligible(s.user_id)
        and (own.scope='any' or (own.scope='city' and s.city_id=actor_city) or (own.scope='state' and pc.state=actor_state))
        and (s.scope='any' or (s.scope='city' and s.city_id=actor_city) or (s.scope='state' and pc.state=actor_state))
        and (lower(coalesce(a.looking_for,'everyone')) = 'everyone'
          or (lower(a.looking_for),lower(p.gender)) in (('men','male'),('women','female'),('men','man'),('women','woman')))
        and (lower(coalesce(p.looking_for,'everyone')) = 'everyone'
          or (lower(p.looking_for),lower(a.gender)) in (('men','male'),('women','female'),('men','man'),('women','woman')))
        and not exists (select 1 from public.user_blocks b
          where (b.blocker_id = actor and b.blocked_id = s.user_id)
             or (b.blocker_id = s.user_id and b.blocked_id = actor))
        and not exists (select 1 from public.connections c
          where (c.user1_id = actor and c.user2_id = s.user_id)
             or (c.user1_id = s.user_id and c.user2_id = actor))
        and not exists (select 1 from private.regional_matchmaker_votes v
          where v.session_id = own.id and v.target_session_id = s.id)
      order by (p.id = p_target) desc nulls last, s.expires_at desc, p.id
      limit 12
    ) q;
  end if;

  if p_action in ('connect','pass') then
    if own.id is null or not (suggestions @> jsonb_build_array(jsonb_build_object('id',p_target))) then
      raise exception 'This suggestion is no longer available';
    end if;
    select * into strict peer from private.regional_matchmaker_sessions
      where user_id = p_target and expires_at > now()
      for share;
    perform 1 from private.regional_matchmaker_sessions where id = own.id for share;
    if not found then raise exception 'Your session has ended'; end if;

    insert into private.regional_matchmaker_votes(session_id,target_session_id,wants_connection)
      values(own.id,peer.id,p_action = 'connect') on conflict do nothing;
    if p_action = 'connect' and exists (
      select 1 from private.regional_matchmaker_votes v
      where v.session_id = peer.id and v.target_session_id = own.id and v.wants_connection
    ) then
      insert into public.connections(user1_id,user2_id) values(least(actor,p_target),greatest(actor,p_target))
        on conflict(user1_id,user2_id) do update set user1_id = excluded.user1_id returning id into connection;
      insert into public.conversations(connection_id) values(connection)
        on conflict(connection_id) do update set connection_id = excluded.connection_id returning id into conversation;
      insert into public.conversation_members(conversation_id,user_id)
        values(conversation,actor),(conversation,p_target) on conflict do nothing;
      matched := true;
    end if;
    select coalesce(jsonb_agg(value),'[]'::jsonb) into suggestions
      from jsonb_array_elements(suggestions) where value->>'id' <> p_target::text;
  end if;

  return jsonb_build_object('active',own.id is not null,'eligible',available,
    'has_photo',exists (select 1 from public.profile_gallery_photos g
      join storage.objects o on o.bucket_id = 'my-photos' and o.name = g.object_path
      where g.user_id = actor and g.for_matchmaker),
    'city_name',(select c.name from public.cities c where c.id=actor_city),
    'state_name',actor_state,'scope',own.scope,
    'expires_at',own.expires_at,'suggestions',suggestions,'matched',matched);
end;
$body$;

-- The photo audience governs profile galleries. Discovery explicitly shares only
-- the chosen photo, and only with people the existing matchmaker suggests.
create function public.can_download_matchmaker_photo(p_path text)
returns boolean language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then return false; end if;
  return (public.spotmate_regional_matchmaker('view')->'suggestions')
    @> jsonb_build_array(jsonb_build_object('matchmaker_photo', p_path));
end;
$$;
revoke all on function public.can_download_matchmaker_photo(text) from public, anon;
grant execute on function public.can_download_matchmaker_photo(text) to authenticated;

alter policy "Gallery objects require a permitted storage operation" on storage.objects
using (
  bucket_id <> 'my-photos'
  or (
    auth.uid() is not null and (
      storage.allow_any_operation(array['object.get_authenticated', 'object.get_authenticated_info'])
      and (
        exists (select 1 from public.profile_gallery_photos p
          where p.object_path = storage.objects.name)
        or public.can_download_matchmaker_photo(name)
      )
      or storage.allow_any_operation(array['object.delete', 'object.delete_many'])
      and (storage.foldername(name))[1] = auth.uid()::text
    )
  )
);

create policy "Matchmaker suggestions can download the selected photo"
on storage.objects for select to authenticated using (
  bucket_id = 'my-photos'
  and storage.allow_any_operation(array['object.get_authenticated', 'object.get_authenticated_info'])
  and public.can_download_matchmaker_photo(name)
);
