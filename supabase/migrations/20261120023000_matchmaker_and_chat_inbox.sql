create table private.matchmaker_sessions (
  user_id uuid primary key references public.user_profiles(id) on delete cascade,
  id uuid not null unique default gen_random_uuid(),
  hotspot_id uuid not null references public.hotspots(id) on delete cascade,
  expires_at timestamptz not null
);
create index matchmaker_active_hotspot_idx on private.matchmaker_sessions (hotspot_id, expires_at);
create table private.matchmaker_votes (
  session_id uuid references private.matchmaker_sessions(id) on delete cascade,
  target_session_id uuid references private.matchmaker_sessions(id) on delete cascade,
  wants_connection boolean not null,
  primary key (session_id, target_session_id)
);
revoke all on private.matchmaker_sessions, private.matchmaker_votes from public, anon, authenticated;

create function private.matchmaker_eligible(p_user uuid, p_hotspot uuid)
returns boolean language sql stable set search_path = '' as $body$
  select exists (
    select 1 from public.hotspot_members m
    join public.hotspots h on h.id = m.hotspot_id
    join public.user_profiles p on p.id = m.user_id
    where m.user_id = p_user and m.hotspot_id = p_hotspot
      and m.status = 'active' and m.expires_at > now()
      and h.status = 'approved' and (h.expires_at is null or h.expires_at > now())
      and p.is_active and p.date_of_birth <= (current_date - interval '18 years')::date
      and not exists (
        select 1 from public.hotspot_room_bans b where b.user_id = p_user
          and b.hotspot_id = p_hotspot and (b.expires_at is null or b.expires_at > now())
      )
  );
$body$;
revoke all on function private.matchmaker_eligible(uuid,uuid) from public, anon, authenticated;

create function public.spotmate_matchmaker(p_action text default 'view', p_target uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $body$
declare
  actor uuid := auth.uid();
  hotspot uuid;
  own private.matchmaker_sessions%rowtype;
  peer private.matchmaker_sessions%rowtype;
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
    delete from private.matchmaker_sessions where user_id = actor;
    return jsonb_build_object('active',false,'suggestions',suggestions);
  end if;

  select m.hotspot_id into hotspot from public.hotspot_members m
    where m.user_id = actor and private.matchmaker_eligible(actor,m.hotspot_id);

  if p_action = 'start' then
    if hotspot is null then raise exception 'Join an eligible hotspot first'; end if;
    delete from private.matchmaker_sessions
      where user_id = actor and (expires_at <= now() or hotspot_id <> hotspot);
    insert into private.matchmaker_sessions(user_id,hotspot_id,expires_at)
      values(actor,hotspot,now()+interval '1 hour') on conflict(user_id) do nothing;
  end if;

  if p_action in ('connect','pass') then
    if p_target is null or p_target = actor then raise exception 'Invalid match candidate'; end if;
    perform pg_advisory_xact_lock(hashtextextended(
      'spotmate-match:'||least(actor,p_target)::text||':'||greatest(actor,p_target)::text,0));
  end if;
  select * into own from private.matchmaker_sessions where user_id = actor
    and hotspot_id = hotspot and expires_at > now();

  if own.id is not null then
    select coalesce(jsonb_agg(to_jsonb(q)), '[]'::jsonb) into suggestions
    from (
      select p.id, p.name, p.bio, p.profile_photo, p.avatar_type, p.avatar_emoticon
      from private.matchmaker_sessions s
      join public.user_profiles p on p.id = s.user_id
      join public.user_profiles a on a.id = actor
      where s.hotspot_id = own.hotspot_id and s.expires_at > now() and s.user_id <> actor
        and private.matchmaker_eligible(s.user_id,s.hotspot_id)
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
        and not exists (select 1 from private.matchmaker_votes v
          where v.session_id = own.id and v.target_session_id = s.id)
      order by (p.id = p_target) desc nulls last, s.expires_at desc, p.id
      limit 12
    ) q;
  end if;

  if p_action in ('connect','pass') then
    if own.id is null or not (suggestions @> jsonb_build_array(jsonb_build_object('id',p_target))) then
      raise exception 'This suggestion is no longer available';
    end if;
    select * into strict peer from private.matchmaker_sessions
      where user_id = p_target and hotspot_id = own.hotspot_id and expires_at > now()
      for share;
    perform 1 from private.matchmaker_sessions where id = own.id for share;
    if not found then raise exception 'Your session has ended'; end if;

    insert into private.matchmaker_votes(session_id,target_session_id,wants_connection)
      values(own.id,peer.id,p_action = 'connect') on conflict do nothing;
    if p_action = 'connect' and exists (
      select 1 from private.matchmaker_votes v
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

  return jsonb_build_object('active',own.id is not null,'eligible',hotspot is not null,
    'hotspot_name',(select h.name from public.hotspots h where h.id = hotspot),
    'expires_at',own.expires_at,'suggestions',suggestions,'matched',matched);
end;
$body$;
revoke all on function public.spotmate_matchmaker(text,uuid) from public, anon, authenticated;
grant execute on function public.spotmate_matchmaker(text,uuid) to authenticated;

create function public.spotmate_direct_inbox()
returns table(conversation_id uuid,connection_id uuid,other_id uuid,other_name text,
  other_photo text,other_avatar_type text,other_avatar_emoticon text,last_message text,
  last_time timestamptz,unread bigint)
language sql stable security invoker set search_path = '' as $body$
  select cv.id, c.id, p.id, coalesce(p.name,'Connection'), p.profile_photo, p.avatar_type,
    p.avatar_emoticon,
    case when cl.created_at is not null and (m.created_at is null or cl.created_at > m.created_at)
      then concat(case when cl.call_type = 'video' then 'Video' else 'Audio' end,' call · ',
        case when cl.end_reason is not null then initcap(cl.end_reason) else initcap(cl.status) end)
      else coalesce(nullif(m.message,''),case when m.attachment_path is not null then 'Attachment'
        when m.image_url is not null then 'Photo' else 'No messages yet' end) end,
    greatest(m.created_at, cl.created_at), coalesce(u.total,0)
  from public.conversation_members member
  join public.conversations cv on cv.id = member.conversation_id
  join public.connections c on c.id = cv.connection_id
  join public.user_profiles p on p.id = case when c.user1_id = auth.uid() then c.user2_id else c.user1_id end
  left join lateral (select m.message,m.created_at,m.attachment_path,m.image_url
    from public.messages m where m.conversation_id = cv.id
    order by m.created_at desc,m.id desc limit 1) m on true
  left join lateral (select cl.call_type,cl.status,cl.end_reason,cl.created_at
    from public.calls cl where cl.conversation_id = cv.id
    order by cl.created_at desc,cl.id desc limit 1) cl on true
  left join lateral (select count(*) total from public.messages m where m.conversation_id = cv.id
    and m.sender_id <> auth.uid() and m.read_at is null) u on true
  where member.user_id = auth.uid() and auth.uid() in (c.user1_id,c.user2_id)
  order by greatest(m.created_at,cl.created_at) desc nulls last,cv.id;
$body$;
revoke all on function public.spotmate_direct_inbox() from public, anon, authenticated;
grant execute on function public.spotmate_direct_inbox() to authenticated;

create table public.spotmate_room_reads (
  user_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  hotspot_id uuid not null references public.hotspots(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key(user_id,hotspot_id)
);
alter table public.spotmate_room_reads enable row level security;
revoke all on public.spotmate_room_reads from public, anon, authenticated;
grant select,insert,update on public.spotmate_room_reads to authenticated;
create policy room_reads_own on public.spotmate_room_reads for all to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));
create function public.spotmate_room_inbox()
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
    and h.status='approved' and (h.expires_at is null or h.expires_at > now())
    and not exists (select 1 from public.hotspot_room_bans b
      where b.hotspot_id=h.id and b.user_id=m.user_id and (b.expires_at is null or b.expires_at > now()));
$body$;
revoke all on function public.spotmate_room_inbox() from public, anon, authenticated;
grant execute on function public.spotmate_room_inbox() to authenticated;

create function public.spotmate_mark_room_read(p_hotspot uuid,p_read_at timestamptz)
returns void language sql security invoker set search_path='' as $body$
  insert into public.spotmate_room_reads(user_id,hotspot_id,read_at)
  select auth.uid(),p_hotspot,coalesce(least(p_read_at,now()),now())
  where exists(select 1 from public.hotspot_members m where m.user_id=auth.uid()
    and m.hotspot_id=p_hotspot and m.status='active' and m.expires_at>now())
  on conflict(user_id,hotspot_id) do update
    set read_at=greatest(public.spotmate_room_reads.read_at,excluded.read_at);
$body$;
revoke all on function public.spotmate_mark_room_read(uuid,timestamptz) from public, anon, authenticated;
grant execute on function public.spotmate_mark_room_read(uuid,timestamptz) to authenticated;
