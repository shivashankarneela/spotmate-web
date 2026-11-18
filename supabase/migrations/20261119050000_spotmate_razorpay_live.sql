begin;

alter table public.spotmate_recharge_orders
  add column refund_state text not null default 'none'
  check (refund_state in ('none', 'review_required', 'processed'));

create table public.spotmate_live_refund_events (
  provider_refund_id text primary key,
  order_id uuid not null references public.spotmate_recharge_orders(id),
  provider_payment_id text not null,
  amount_paise integer not null check (amount_paise > 0),
  status text not null check (status in ('review_required', 'applied')),
  reason text,
  created_at timestamptz not null default now()
);
alter table public.spotmate_live_refund_events enable row level security;
revoke all on public.spotmate_live_refund_events from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.spotmate_record_failed_payment_live(p_provider_order_id text, p_provider_payment_id text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_order public.spotmate_recharge_orders%rowtype;
begin
 if p_provider_order_id is null or p_provider_payment_id is null or p_provider_payment_id='' then raise exception 'Invalid failed payment'; end if;
 select * into v_order from public.spotmate_recharge_orders
 where provider='razorpay_live' and provider_order_id=p_provider_order_id for update;
 if not found then return false; end if;
 if v_order.status in ('paid','refunded') then return false; end if;
 insert into public.spotmate_test_payment_attempts(provider_payment_id,order_id,status)
 values (p_provider_payment_id,v_order.id,'failed') on conflict (provider_payment_id) do nothing;
 if v_order.status='pending' then
   update public.spotmate_recharge_orders set status='failed' where id=v_order.id;
   return true;
 end if;
 return false;
end $function$;

CREATE OR REPLACE FUNCTION public.spotmate_record_refund_live(p_provider_refund_id text, p_provider_payment_id text, p_amount_paise integer)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_order public.spotmate_recharge_orders%rowtype;
declare v_balance integer;
declare v_result text;
begin
 if coalesce(p_provider_refund_id,'')='' or coalesce(p_provider_payment_id,'')='' or p_amount_paise is null or p_amount_paise<=0 then raise exception 'Invalid refund details'; end if;
 select * into v_order from public.spotmate_recharge_orders
 where provider='razorpay_live' and provider_payment_id=p_provider_payment_id for update;
 if not found then return 'unmatched'; end if;
 select status into v_result from public.spotmate_live_refund_events where provider_refund_id=p_provider_refund_id;
 if found then return v_result; end if;
 if p_amount_paise>v_order.amount_paise then raise exception 'Refund exceeds payment'; end if;
 if p_amount_paise<>v_order.amount_paise or v_order.status<>'paid' or v_order.refund_state<>'none' then
  insert into public.spotmate_live_refund_events(provider_refund_id,order_id,provider_payment_id,amount_paise,status,reason)
  values(p_provider_refund_id,v_order.id,p_provider_payment_id,p_amount_paise,'review_required','Partial refund or order already reconciled');
  if v_order.status='paid' then update public.spotmate_recharge_orders set refund_state='review_required' where id=v_order.id; end if;
  return 'review_required';
 end if;
 select balance into v_balance from public.wallets where user_id=v_order.user_id for update;
 if v_balance is null or v_balance<v_order.credits then
  insert into public.spotmate_live_refund_events(provider_refund_id,order_id,provider_payment_id,amount_paise,status,reason)
  values(p_provider_refund_id,v_order.id,p_provider_payment_id,p_amount_paise,'review_required','Insufficient unspent credits');
  update public.spotmate_recharge_orders set status='refunded',refund_state='review_required' where id=v_order.id;
  return 'review_required';
 end if;
 update public.wallets set balance=balance-v_order.credits,updated_at=now() where user_id=v_order.user_id;
 insert into public.wallet_transactions(user_id,amount,transaction_type,description)
 values(v_order.user_id,-v_order.credits,'refund','Razorpay live refund '||p_provider_refund_id);
 update public.spotmate_recharge_orders set status='refunded',refund_state='processed' where id=v_order.id;
 insert into public.spotmate_live_refund_events(provider_refund_id,order_id,provider_payment_id,amount_paise,status)
 values(p_provider_refund_id,v_order.id,p_provider_payment_id,p_amount_paise,'applied');
 return 'applied';
end $function$;

CREATE OR REPLACE FUNCTION public.spotmate_settle_razorpay_live(p_order_id uuid, p_provider_order_id text, p_amount_paise integer, p_provider_payment_id text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_order public.spotmate_recharge_orders%rowtype;
begin
 if p_provider_payment_id is null or p_provider_payment_id='' then raise exception 'Missing payment reference'; end if;
 select * into v_order from public.spotmate_recharge_orders where id=p_order_id for update;
 if not found or v_order.provider is distinct from 'razorpay_live'
 or v_order.provider_order_id is distinct from p_provider_order_id
 or v_order.amount_paise is distinct from p_amount_paise
 or v_order.currency <> 'INR' or v_order.credits <= 0 then
    raise exception 'Payment does not match recharge order';
 end if;
 if v_order.status='paid' or v_order.status='refunded' then
   if v_order.provider_payment_id is distinct from p_provider_payment_id then raise exception 'Order already settled with different payment'; end if;
   return false;
 end if;
 if v_order.status not in ('pending','failed') then raise exception 'Order is not eligible for settlement'; end if;
 update public.spotmate_recharge_orders set status='paid',paid_at=now(),provider_payment_id=p_provider_payment_id where id=p_order_id;
 insert into public.wallets(user_id,balance) values (v_order.user_id,v_order.credits)
 on conflict(user_id) do update set balance=public.wallets.balance+excluded.balance,updated_at=now();
 insert into public.wallet_transactions(user_id,amount,transaction_type,description)
 values(v_order.user_id,v_order.credits,'recharge','Razorpay live recharge '||p_provider_order_id);
 return true;
end $function$;

revoke all on function public.spotmate_record_failed_payment_live(text,text) from public, anon, authenticated;
grant execute on function public.spotmate_record_failed_payment_live(text,text) to service_role;
revoke all on function public.spotmate_record_refund_live(text,text,integer) from public, anon, authenticated;
grant execute on function public.spotmate_record_refund_live(text,text,integer) to service_role;
revoke all on function public.spotmate_settle_razorpay_live(uuid,text,integer,text) from public, anon, authenticated;
grant execute on function public.spotmate_settle_razorpay_live(uuid,text,integer,text) to service_role;

commit;
