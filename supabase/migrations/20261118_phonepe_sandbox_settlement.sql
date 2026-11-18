-- Apply only to a disposable sandbox clone until the payment flow is tested.
-- Never activate production packages as part of this migration.
create unique index if not exists spotmate_recharge_phonepe_order_uidx
  on public.spotmate_recharge_orders (provider_order_id)
  where provider_order_id is not null;
create unique index if not exists spotmate_recharge_phonepe_payment_uidx
  on public.spotmate_recharge_orders (provider_payment_id)
  where provider_payment_id is not null;

-- Service-role-only RPC. Single DB transaction locks order, grants credits once,
-- and writes the ledger. Client-supplied amounts or balances are never trusted.
create or replace function public.spotmate_settle_phonepe_sandbox(
  p_order_id uuid, p_merchant_order_id text, p_amount_paise integer,
  p_payment_id text default null
)
returns boolean
language plpgsql security definer set search_path = ''
as $$
declare v_order public.spotmate_recharge_orders%rowtype;
begin
  select * into v_order from public.spotmate_recharge_orders
    where id=p_order_id for update;
  if not found or v_order.provider is distinct from 'phonepe_sandbox'
    or v_order.provider_order_id is distinct from p_merchant_order_id
    or v_order.amount_paise is distinct from p_amount_paise
    or v_order.currency <> 'INR'
    or v_order.credits <= 0 then
    raise exception 'Payment does not match the original recharge order';
  end if;
  if v_order.status = 'paid' then return false; end if;
  if v_order.status <> 'pending' then
    raise exception 'Recharge order is not pending';
  end if;
  update public.spotmate_recharge_orders
     set status='paid', paid_at=now(), provider_payment_id=p_payment_id
   where id=p_order_id;
  insert into public.wallets(user_id,balance)
    values(v_order.user_id,v_order.credits)
    on conflict (user_id) do update
      set balance=public.wallets.balance + excluded.balance,
          updated_at=now();
  insert into public.wallet_transactions(user_id,amount,transaction_type,description)
    values(v_order.user_id,v_order.credits,'recharge',
           'PhonePe sandbox recharge ' || p_merchant_order_id);
  return true;
end;
$$;
revoke all on function public.spotmate_settle_phonepe_sandbox(uuid,text,integer,text)
  from public, anon, authenticated;
grant execute on function public.spotmate_settle_phonepe_sandbox(uuid,text,integer,text)
  to service_role;
