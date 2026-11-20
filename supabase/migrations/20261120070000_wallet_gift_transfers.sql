CREATE OR REPLACE FUNCTION private.grant_signup_welcome_credits(p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare awarded uuid;
begin
 insert into public.wallets(user_id, balance) values(p_user_id, 0)
 on conflict(user_id) do nothing;
 insert into public.wallet_transactions(user_id, amount, transaction_type, description)
 values(p_user_id,50,'welcome_bonus','Spotmate signup welcome gift')
 on conflict do nothing returning id into awarded;
 if awarded is not null then
  update public.wallets set balance=balance+50, updated_at=now()
   where user_id=p_user_id;
 end if;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.send_spotmate_gift(p_hotspot_id uuid, p_recipient_id uuid, p_gift_id text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid:=auth.uid(); cost integer; item uuid; bal integer;
begin
 if uid is null or p_recipient_id=uid then raise exception 'Invalid recipient'; end if;
 if not exists(select 1 from public.user_profiles where id=p_recipient_id and is_active) then raise exception 'Recipient unavailable'; end if;
 if not exists(select 1 from public.hotspots h where h.id=p_hotspot_id and h.status='approved' and
   (h.hotspot_type='place' or h.expires_at>now())) then raise exception 'Room unavailable'; end if;
 if exists(select 1 from public.user_blocks b where
   (b.blocker_id=uid and b.blocked_id=p_recipient_id) or (b.blocker_id=p_recipient_id and b.blocked_id=uid))
 then raise exception 'Gift not allowed'; end if;
 if exists(select 1 from public.hotspot_room_bans b where b.hotspot_id=p_hotspot_id and b.user_id=uid
 and (b.expires_at is null or b.expires_at>now())) then raise exception 'Not allowed in this room'; end if;
 select price_credits into cost from public.spotmate_gifts where id=p_gift_id and active=true;
 if cost is null then raise exception 'Gift unavailable'; end if;
 insert into public.wallets(user_id,balance) values(p_recipient_id,0) on conflict(user_id) do nothing;
 perform user_id from public.wallets where user_id in (uid,p_recipient_id) order by user_id for update;
 select balance into bal from public.wallets where user_id=uid for update;
 if bal is null or bal<cost then raise exception 'Insufficient credits'; end if;
 update public.wallets set balance=balance-cost,updated_at=now() where user_id=uid;
 insert into public.spotmate_gift_transactions(sender_id,recipient_id,hotspot_id,gift_id,credit_cost)
 values(uid,p_recipient_id,p_hotspot_id,p_gift_id,cost) returning id into item;
 insert into public.wallet_transactions(user_id,amount,transaction_type,description)
 values(uid,-cost,'gift','Sent '||p_gift_id||' to another member');
 update public.wallets set balance=balance+cost,updated_at=now() where user_id=p_recipient_id;
 insert into public.wallet_transactions(user_id,amount,transaction_type,description)
 values(p_recipient_id,cost,'gift','Received '||p_gift_id||' from another member');
 return item;
end $function$
;
create or replace function public.transfer_spotmate_gift(p_hotspot_id uuid,p_recipient_id uuid,p_gift_id text)
returns uuid language sql security invoker set search_path='' as $$
 select public.send_spotmate_gift(p_hotspot_id,p_recipient_id,p_gift_id)
$$;
revoke all on function public.transfer_spotmate_gift(uuid,uuid,text) from public,anon;
grant execute on function public.transfer_spotmate_gift(uuid,uuid,text) to authenticated;
