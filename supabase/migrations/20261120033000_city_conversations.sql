alter table public.hotspots
 add column is_city_chat boolean not null default false,
 add column city_palette text not null default 'teal' check (city_palette in ('teal','navy','charcoal')),
 add column city_background text not null default 'paper' check (city_background in ('paper','mist','sand')),
 add column city_banner text not null default 'none' check (city_banner in ('none','welcome','say_hello')),
 add constraint city_chat_stays_open check (
   not is_city_chat or (owner_id is null and not is_locked and expires_at is null
     and hotspot_type='place' and status='approved' and not checkin_enabled)
 );
create unique index one_public_chat_per_city on public.hotspots(city_id) where is_city_chat;

insert into public.hotspots(city_id,name,status,hotspot_type,is_city_chat)
select id, case name
 when 'Hyderabad' then 'Hyderabadi Biryani' when 'Bengaluru' then 'Filter Coffee'
 when 'Mumbai' then 'Vada Pav' when 'Warangal' then 'Kakatiya Arch'
 when 'Vijayawada' then 'Kanaka Durga Hills' when 'Visakhapatnam' then 'RK Beach'
 when 'Chennai' then 'Marina Beach' when 'Kochi' then 'Fort Kochi'
 when 'Coimbatore' then 'Kongu Kitchen' when 'Pune' then 'Misal Pav'
 when 'New Delhi' then 'Chandni Chowk' when 'Kolkata' then 'College Street'
 when 'Ahmedabad' then 'Manek Chowk' when 'Jaipur' then 'Pink City'
 when 'Lucknow' then 'Awadhi Kitchen' else name end,
 'approved','place',true
from public.cities where is_active
on conflict (city_id) where is_city_chat do nothing;


create table public.private_chat_room_visits (
 user_id uuid not null references auth.users(id) on delete cascade,
 hotspot_id uuid not null references public.hotspots(id) on delete cascade,
 joined_at timestamptz not null,
 expires_at timestamptz not null,
 primary key(user_id,hotspot_id)
);
alter table public.private_chat_room_visits enable row level security;
revoke all on public.private_chat_room_visits from public,anon,authenticated;
grant select on public.private_chat_room_visits to authenticated;
create policy private_chat_room_visits_own on public.private_chat_room_visits
for select to authenticated using (user_id=(select auth.uid()));
insert into public.private_chat_room_visits
select m.user_id,m.hotspot_id,m.joined_at,m.expires_at
from public.hotspot_members m join public.hotspots h on h.id=m.hotspot_id
where m.status='active' and m.expires_at>now() and h.hotspot_type='community'
on conflict do nothing;

create function private.track_private_chat_room_visit() returns trigger
language plpgsql security definer set search_path='' as $body$
begin
 if tg_op='DELETE' then
   delete from public.private_chat_room_visits where user_id=old.user_id and hotspot_id=old.hotspot_id;
   return old;
 end if;
 if new.status='active' and exists(select 1 from public.hotspots h where h.id=new.hotspot_id and h.hotspot_type='community') then
   insert into public.private_chat_room_visits(user_id,hotspot_id,joined_at,expires_at)
     values(new.user_id,new.hotspot_id,new.joined_at,new.expires_at)
     on conflict(user_id,hotspot_id) do update set expires_at=excluded.expires_at,
       joined_at=case when public.private_chat_room_visits.expires_at>now()
           then public.private_chat_room_visits.joined_at else excluded.joined_at end;
 elsif new.status<>'active' then
   delete from public.private_chat_room_visits where user_id=new.user_id and hotspot_id=new.hotspot_id;
 end if;
 return new;
end;
$body$;
revoke all on function private.track_private_chat_room_visit() from public,anon,authenticated;
create trigger track_private_chat_room_visit after insert or update of hotspot_id,status,expires_at or delete on public.hotspot_members
for each row execute function private.track_private_chat_room_visit();

create function private.provision_city_conversation() returns trigger
language plpgsql security definer set search_path='' as $body$
begin
 if new.is_active then
   insert into public.hotspots(city_id,name,status,hotspot_type,is_city_chat)
     values(new.id,new.name,'approved','place',true)
     on conflict(city_id) where is_city_chat do nothing;
 end if;
 return new;
end;
$body$;
revoke all on function private.provision_city_conversation() from public,anon,authenticated;
create trigger provision_city_conversation after insert or update of is_active on public.cities
for each row execute function private.provision_city_conversation();
CREATE OR REPLACE FUNCTION public.join_hotspot_room(p_hotspot_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid:=auth.uid(); r record; previously_joined boolean; session_end timestamptz;
begin
 if uid is null then raise exception 'Sign in required'; end if;
 select h.id,h.owner_id,h.hotspot_type,h.expires_at,h.status,h.is_locked
 into r from public.hotspots h where h.id=p_hotspot_id for share;
 if not found or r.status<>'approved' or
  (r.hotspot_type='community' and r.expires_at<=now())
 then raise exception 'Room is unavailable'; end if;
 if not exists(select 1 from public.user_profiles p where p.id=uid and p.is_active=true)
 then raise exception 'Complete your profile first'; end if;
 if exists(select 1 from public.hotspot_room_bans b
   where b.hotspot_id=p_hotspot_id and b.user_id=uid
   and (b.expires_at is null or b.expires_at>now())) then
   raise exception 'You cannot enter this room'; end if;
 select exists(select 1 from public.hotspot_members m
   where m.hotspot_id=p_hotspot_id and m.user_id=uid
   and m.status='active' and m.expires_at>now()) or exists(select 1 from public.private_chat_room_visits v
   where v.hotspot_id=p_hotspot_id and v.user_id=uid and v.expires_at>now()) into previously_joined;
 if r.hotspot_type='community' and r.is_locked and
   uid is distinct from r.owner_id and not previously_joined then
   raise exception 'The owner locked this room. New members cannot join right now'; end if;
 session_end:=case when r.hotspot_type='community' then least(now()+interval '12 hours',r.expires_at)
 else now()+interval '12 hours' end;
 insert into public.hotspot_members(hotspot_id,user_id,status,joined_at,last_seen_at,expires_at)
 values(p_hotspot_id,uid,'active',now(),now(),session_end)
 on conflict(user_id) do update set hotspot_id=excluded.hotspot_id,
 status='active',joined_at=excluded.joined_at,last_seen_at=excluded.last_seen_at,
 expires_at=excluded.expires_at;
 return jsonb_build_object('success',true,'expires_at',session_end);
end$function$;
create or replace function public.spotmate_room_inbox()
returns table(hotspot_id uuid,name text,image_url text,last_message text,last_time timestamptz,unread bigint)
language sql stable security definer set search_path = '' as $body$
  select h.id,h.name,h.image_url,coalesce(latest.body,'No messages yet'),latest.created_at,coalesce(u.total,0)
  from public.private_chat_room_visits m join public.hotspots h on h.id=m.hotspot_id
  left join public.spotmate_room_reads r on r.user_id=m.user_id and r.hotspot_id=h.id
  left join lateral (select x.body,x.created_at from public.hotspot_messages x
    where x.hotspot_id=h.id and x.deleted_at is null
    order by x.created_at desc,x.id desc limit 1) latest on true
  left join lateral (select count(*) total from public.hotspot_messages x
    where x.hotspot_id=h.id and x.deleted_at is null and x.sender_id <> m.user_id
      and x.created_at > greatest(m.joined_at,r.read_at)) u on true
  where m.user_id=auth.uid() and m.expires_at > now()
    and h.hotspot_type='community' and h.status='approved' and (h.expires_at is null or h.expires_at > now())
    and not exists (select 1 from public.hotspot_room_bans b
      where b.hotspot_id=h.id and b.user_id=m.user_id and (b.expires_at is null or b.expires_at > now()));
$body$;

create function public.find_spotmate_people(p_query text)
returns table(id uuid,name text,spotmate_id text,profile_photo text,avatar_type text,avatar_emoticon text)
language sql stable security invoker set search_path='' as $body$
 select p.id,p.name,p.spotmate_id,p.profile_photo,p.avatar_type,p.avatar_emoticon
 from public.user_profiles p
 where auth.uid() is not null and p.id<>auth.uid() and p.is_active
   and length(trim(p_query)) between 2 and 64
   and (strpos(lower(p.name),lower(trim(p_query)))>0
      or lower(p.spotmate_id)=lower(trim(p_query)))
   and not exists(select 1 from public.user_blocks b
     where (b.blocker_id=auth.uid() and b.blocked_id=p.id)
        or (b.blocked_id=auth.uid() and b.blocker_id=p.id))
 order by (lower(p.spotmate_id)=lower(trim(p_query))) desc nulls last,p.name,p.id
 limit 30;
$body$;
revoke all on function public.find_spotmate_people(text) from public,anon,authenticated;
grant execute on function public.find_spotmate_people(text) to authenticated;

create table private.city_chat_customizations (
 user_id uuid not null references auth.users(id) on delete cascade,
 request_id uuid not null,
 primary key(user_id,request_id)
);
revoke all on private.city_chat_customizations from public,anon,authenticated;

create function public.customize_city_chat(p_room uuid,p_category text,p_value text,p_request uuid)
returns integer language plpgsql security definer set search_path='' as $body$
declare
 actor uuid := auth.uid();
 cost integer;
 remaining integer;
 room public.hotspots%rowtype;
begin
 if actor is null or p_request is null then raise exception 'Sign in required'; end if;
 if not private.is_active_hotspot_member(p_room) then raise exception 'Enter the chat first'; end if;
 select * into room from public.hotspots where id=p_room and is_city_chat for update;
 if not found then raise exception 'City chat unavailable'; end if;
 cost := case
   when p_category='palette' and p_value in ('teal','navy','charcoal') then 10
   when p_category='background' and p_value in ('paper','mist','sand') then 15
   when p_category='banner' and p_value in ('none','welcome','say_hello') then 20
   else null end;
 if cost is null then raise exception 'Unknown customization'; end if;
 insert into private.city_chat_customizations(user_id,request_id) values(actor,p_request)
   on conflict do nothing;
 if not found or
    (p_category='palette' and room.city_palette=p_value) or
    (p_category='background' and room.city_background=p_value) or
    (p_category='banner' and room.city_banner=p_value) then
   return coalesce((select w.balance from public.wallets w where w.user_id=actor),0);
 end if;
 update public.wallets set balance=balance-cost,updated_at=now()
   where user_id=actor and balance>=cost returning balance into remaining;
 if not found then raise exception 'Insufficient credits'; end if;
 insert into public.wallet_transactions(user_id,amount,transaction_type,description)
   values(actor,-cost,'adjustment','City chat customization: '||p_category);
 update public.hotspots set
   city_palette=case when p_category='palette' then p_value else city_palette end,
   city_background=case when p_category='background' then p_value else city_background end,
   city_banner=case when p_category='banner' then p_value else city_banner end
 where id=p_room and is_city_chat;
 return remaining;
end;
$body$;
revoke all on function public.customize_city_chat(uuid,text,text,uuid) from public,anon,authenticated;
grant execute on function public.customize_city_chat(uuid,text,text,uuid) to authenticated;

create or replace function public.spotmate_room_directory()
returns table(id uuid,name text,description text,city_id uuid,city_name text,state text,
  is_locked boolean,owner_id uuid,joined boolean,member_count bigint)
language sql stable security definer set search_path='' as $body$
  select h.id,h.name,h.description,c.id,c.name,c.state,h.is_locked,h.owner_id,
    (coalesce(bool_or(m.user_id=auth.uid()),false) or exists(
      select 1 from public.private_chat_room_visits v where v.hotspot_id=h.id and v.user_id=auth.uid() and v.expires_at>now())),
    count(m.user_id)
  from public.hotspots h join public.cities c on c.id=h.city_id
  left join public.hotspot_members m on m.hotspot_id=h.id and m.status='active' and m.expires_at>now()
  where auth.uid() is not null and h.hotspot_type='community' and h.status='approved'
    and h.expires_at>now()
  group by h.id,c.id
  order by count(m.user_id) desc,h.name,h.id;
$body$;
