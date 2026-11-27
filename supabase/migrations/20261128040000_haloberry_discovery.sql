create table private.haloberry_discovery_sessions (
  user_id uuid primary key references public.user_profiles(id) on delete cascade,
  id uuid not null unique default gen_random_uuid()
);
create table private.haloberry_discovery_votes (
  session_id uuid references private.haloberry_discovery_sessions(id) on delete cascade,
  target_session_id uuid references private.haloberry_discovery_sessions(id) on delete cascade,
  wants_connection boolean not null,
  primary key (session_id, target_session_id)
);
revoke all on private.haloberry_discovery_sessions, private.haloberry_discovery_votes
  from public, anon, authenticated;

create or replace function public.haloberry_matchmaker(p_action text default 'view', p_target uuid default null, p_scope text default null)
returns jsonb language plpgsql security definer set search_path = '' as $body$
declare
  actor uuid := auth.uid();
  actor_city uuid;
  actor_state text;
  available boolean;
  own private.haloberry_discovery_sessions%rowtype;
  peer private.haloberry_discovery_sessions%rowtype;
  suggestions jsonb := '[]'::jsonb;
  connection uuid;
  conversation uuid;
  matched boolean := false;
begin
  if actor is null then raise exception 'Sign in required'; end if;
  if p_action is null or p_action not in ('view','start','stop','connect','pass') then
    raise exception 'Invalid matchmaker action';
  end if;
  if p_action in ('start','stop') then
    perform pg_advisory_xact_lock(hashtextextended('haloberry-discovery:' || actor::text, 0));
  end if;
  if p_action = 'stop' then
    delete from private.haloberry_discovery_sessions where user_id = actor;
    p_action := 'view';
  end if;

  select p.city_id, c.state into actor_city, actor_state
    from public.user_profiles p left join public.cities c on c.id=p.city_id where p.id=actor;
  available := exists (select 1 from public.user_profiles p where p.id=actor and p.is_active and p.date_of_birth <= (current_date - interval '18 years')::date) and actor_city is not null;
  if p_action = 'start' then
    if not available then raise exception 'An adult profile and city are required'; end if;
    insert into private.haloberry_discovery_sessions(user_id)
      values(actor) on conflict(user_id) do nothing;
  end if;

  if p_action in ('connect','pass') then
    if p_target is null or p_target = actor then raise exception 'Invalid match candidate'; end if;
    perform pg_advisory_xact_lock(hashtextextended(
      'spotmate-match:'||least(actor,p_target)::text||':'||greatest(actor,p_target)::text,0));
  end if;
  select * into own from private.haloberry_discovery_sessions where user_id = actor
    and available;

  if own.id is not null then
    select coalesce(jsonb_agg(to_jsonb(q) - 'rank' order by q.rank, q.id), '[]'::jsonb) into suggestions
    from (
      select p.id, p.name, p.avatar_emoticon, pc.name as city_name,
        (p.city_id = actor_city) as local,
        case when p.city_id=actor_city then 0 when pc.state=actor_state then 1 else 2 end as rank
      from private.haloberry_discovery_sessions s
      join public.user_profiles p on p.id = s.user_id
      join public.user_profiles a on a.id = actor
      join public.cities pc on pc.id = p.city_id
      where s.user_id <> actor
        and p.is_active and p.date_of_birth <= (current_date - interval '18 years')::date
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
        and not exists (select 1 from private.haloberry_discovery_votes v
          where v.session_id = own.id and v.target_session_id = s.id)
      order by (p.id = p_target) desc nulls last, rank, p.id
      limit 12
    ) q;
  end if;

  if p_action in ('connect','pass') then
    if own.id is null or not (suggestions @> jsonb_build_array(jsonb_build_object('id',p_target))) then
      raise exception 'This suggestion is no longer available';
    end if;
    select * into strict peer from private.haloberry_discovery_sessions
      where user_id = p_target
      for share;
    perform 1 from private.haloberry_discovery_sessions where id = own.id for share;
    if not found then raise exception 'Your session has ended'; end if;

    insert into private.haloberry_discovery_votes(session_id,target_session_id,wants_connection)
      values(own.id,peer.id,p_action = 'connect') on conflict do nothing;
    if p_action = 'connect' and exists (
      select 1 from private.haloberry_discovery_votes v
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
    'state_name',actor_state,
    'suggestions',suggestions,'matched',matched);
end;
$body$;

revoke all on function public.haloberry_matchmaker(text,uuid,text) from public, anon;
grant execute on function public.haloberry_matchmaker(text,uuid,text) to authenticated;

