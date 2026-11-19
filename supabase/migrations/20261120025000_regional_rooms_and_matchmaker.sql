insert into public.cities(name,state) values
 ('Warangal','Telangana'),('Vijayawada','Andhra Pradesh'),('Visakhapatnam','Andhra Pradesh'),
 ('Chennai','Tamil Nadu'),('Kochi','Kerala'),('Coimbatore','Tamil Nadu'),('Pune','Maharashtra'),
 ('New Delhi','Delhi'),('Kolkata','West Bengal'),('Ahmedabad','Gujarat'),('Jaipur','Rajasthan'),
 ('Lucknow','Uttar Pradesh')
on conflict (name,state) do nothing;

create table private.regional_matchmaker_sessions (
 user_id uuid primary key references public.user_profiles(id) on delete cascade,
 id uuid not null unique default gen_random_uuid(),
 city_id uuid not null references public.cities(id) on delete cascade,
 scope text not null check (scope in ('city','state','any')),
 expires_at timestamptz not null
);
create index regional_matchmaker_expiry on private.regional_matchmaker_sessions(expires_at,city_id);
create table private.regional_matchmaker_votes (
 session_id uuid references private.regional_matchmaker_sessions(id) on delete cascade,
 target_session_id uuid references private.regional_matchmaker_sessions(id) on delete cascade,
 wants_connection boolean not null,
 primary key (session_id,target_session_id)
);
revoke all on private.regional_matchmaker_sessions,private.regional_matchmaker_votes from public,anon,authenticated;

create function private.regional_matchmaker_eligible(p_user uuid)
returns boolean language sql stable set search_path='' as $body$
 select exists (
  select 1 from public.user_profiles p
  join storage.objects o on o.bucket_id='profile_photos'
    and o.name=split_part(split_part(p.profile_photo,'/storage/v1/object/public/profile_photos/',2),'?',1)
    and o.name like p.id::text || '/avatar.%'
  where p.id=p_user and p.is_active and p.city_id is not null
    and p.date_of_birth <= (current_date-interval '18 years')::date
 );
$body$;
revoke all on function private.regional_matchmaker_eligible(uuid) from public,anon,authenticated;

create function public.spotmate_regional_matchmaker(p_action text default 'view', p_target uuid default null, p_scope text default null)
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
      select p.id, p.name, p.bio, p.profile_photo, 'photo'::text as avatar_type,
        p.avatar_emoticon, pc.name as city_name, pc.state as state_name
      from private.regional_matchmaker_sessions s
      join public.user_profiles p on p.id = s.user_id
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
    'city_name',(select c.name from public.cities c where c.id=actor_city),
    'state_name',actor_state,'scope',own.scope,
    'expires_at',own.expires_at,'suggestions',suggestions,'matched',matched);
end;
$body$;
revoke all on function public.spotmate_regional_matchmaker(text,uuid,text) from public, anon, authenticated;
grant execute on function public.spotmate_regional_matchmaker(text,uuid,text) to authenticated;


create function public.spotmate_room_directory()
returns table(id uuid,name text,description text,city_id uuid,city_name text,state text,
  is_locked boolean,owner_id uuid,joined boolean,member_count bigint)
language sql stable security definer set search_path='' as $body$
  select h.id,h.name,h.description,c.id,c.name,c.state,h.is_locked,h.owner_id,
    coalesce(bool_or(m.user_id=auth.uid()),false),count(m.user_id)
  from public.hotspots h join public.cities c on c.id=h.city_id
  left join public.hotspot_members m on m.hotspot_id=h.id and m.status='active' and m.expires_at>now()
  where auth.uid() is not null and h.hotspot_type='community' and h.status='approved'
    and h.expires_at>now()
  group by h.id,c.id
  order by count(m.user_id) desc,h.name,h.id;
$body$;
revoke all on function public.spotmate_room_directory() from public,anon,authenticated;
grant execute on function public.spotmate_room_directory() to authenticated;

alter table public.hotspot_message_reactions drop constraint hotspot_message_reactions_reaction_check;
alter table public.hotspot_message_reactions add constraint hotspot_message_reactions_reaction_check
  check (reaction in ('like','heart','laugh','wow','sad','fire'));

create function public.spotmate_set_room_reaction(p_message uuid,p_reaction text)
returns void language plpgsql security invoker set search_path='' as $body$
declare actor uuid := auth.uid();
begin
  if actor is null then raise exception 'Sign in required'; end if;
  perform pg_advisory_xact_lock(hashtextextended(actor::text||':'||p_message::text,0));
  delete from public.hotspot_message_reactions where message_id=p_message and user_id=actor;
  if p_reaction is not null then
    insert into public.hotspot_message_reactions(message_id,user_id,reaction)
      values(p_message,actor,p_reaction);
  end if;
end;
$body$;
revoke all on function public.spotmate_set_room_reaction(uuid,text) from public,anon,authenticated;
grant execute on function public.spotmate_set_room_reaction(uuid,text) to authenticated;

create or replace function public.spotmate_room_inbox()
returns table(hotspot_id uuid,name text,image_url text,last_message text,last_time timestamptz,unread bigint)
language sql stable security invoker set search_path = '' as $body$
  select h.id,h.name,h.image_url,coalesce(latest.body,'No messages yet'),latest.created_at,coalesce(u.total,0)
  from public.hotspot_members m join public.hotspots h on h.id=m.hotspot_id
  left join public.spotmate_room_reads r on r.user_id=m.user_id and r.hotspot_id=h.id
  left join lateral (select x.body,x.created_at from public.hotspot_messages x
    where x.hotspot_id=h.id and x.deleted_at is null
    order by x.created_at desc,x.id desc limit 1) latest on true
  left join lateral (select count(*) total from public.hotspot_messages x
    where x.hotspot_id=h.id and x.deleted_at is null and x.sender_id <> m.user_id
      and x.created_at > greatest(m.joined_at,r.read_at)) u on true
  where m.user_id=auth.uid() and m.status='active' and m.expires_at > now()
    and h.hotspot_type='community' and h.status='approved' and (h.expires_at is null or h.expires_at > now())
    and not exists (select 1 from public.hotspot_room_bans b
      where b.hotspot_id=h.id and b.user_id=m.user_id and (b.expires_at is null or b.expires_at > now()));
$body$;
