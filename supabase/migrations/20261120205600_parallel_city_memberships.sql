alter table public.hotspot_members drop constraint hotspot_members_user_id_key,
 add unique(user_id,hotspot_id);
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
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,3));
 if not exists(select from public.hotspots where id=p_hotspot_id and is_city_chat) then
  delete from public.hotspot_members m using public.hotspots h where m.hotspot_id=h.id and m.user_id=uid and not coalesce(h.is_city_chat,false) and h.id<>p_hotspot_id;
 end if;
 insert into public.hotspot_members(hotspot_id,user_id,status,joined_at,last_seen_at,expires_at)
 values(p_hotspot_id,uid,'active',now(),now(),session_end)
 on conflict(user_id,hotspot_id) do update set hotspot_id=excluded.hotspot_id,
 status='active',joined_at=excluded.joined_at,last_seen_at=excluded.last_seen_at,
 expires_at=excluded.expires_at;
 return jsonb_build_object('success',true,'expires_at',session_end);
end$function$;
CREATE OR REPLACE FUNCTION public.join_hotspot_with_pin(p_hotspot_id uuid, p_pin text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare u uuid; secured_hash text; expires timestamptz; recent_attempts int;
begin
 u:=auth.uid();
 if u is null then raise exception 'Authentication required'; end if;
 if p_pin is null or p_pin !~ '^[0-9]{4,8}$' then raise exception 'Invalid PIN format'; end if;
 if not exists(select 1 from public.hotspots where id=p_hotspot_id and status='approved' and checkin_enabled=true)
 then raise exception 'Check-in is not enabled at this venue'; end if;
 select count(*) into recent_attempts from private.hotspot_pin_attempts where user_id=u and hotspot_id=p_hotspot_id and attempted_at>now()-interval '15 minutes';
 if recent_attempts>=5 then raise exception 'Too many attempts. Try again in 15 minutes'; end if;
 insert into private.hotspot_pin_attempts(user_id,hotspot_id) values(u,p_hotspot_id);
 select pin_hash into secured_hash from private.hotspot_credentials where hotspot_id=p_hotspot_id;
 if secured_hash is null or public.crypt(p_pin,secured_hash) is distinct from secured_hash then raise exception 'Invalid venue PIN'; end if;
 expires:=now()+interval '1 hour';
 delete from public.hotspot_members m using public.hotspots h where m.hotspot_id=h.id and m.user_id=u and not coalesce(h.is_city_chat,false);
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,3));
 insert into public.hotspot_members(hotspot_id,user_id,status,joined_at,last_seen_at,expires_at)
 values(p_hotspot_id,u,'active',now(),now(),expires);
 return jsonb_build_object('success',true,'expires_at',expires);
end$function$;
CREATE OR REPLACE FUNCTION public.leave_hotspot()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 delete from public.hotspot_members m using public.hotspots h where m.hotspot_id=h.id and m.user_id=auth.uid() and not coalesce(h.is_city_chat,false);
end$function$;
