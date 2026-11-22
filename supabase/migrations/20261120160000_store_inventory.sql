create table public.store_items (
 id text primary key, title text not null, category text not null,
 prices integer[] not null check(cardinality(prices)=4 and 0 < all(prices))
);
insert into public.store_items values
 ('teal_scarf','Teal scarf','Costumes','{2,4,7,20}'),
 ('beagle','Beagle','Pets','{3,6,10,30}'),
 ('commuter','City Commuter','Vehicles','{5,10,18,45}');
create table public.store_inventory (
 user_id uuid references auth.users on delete cascade, item_id text references public.store_items,
 expires_at timestamptz, equipped boolean not null default false, primary key(user_id,item_id)
);
create table public.store_receipts (
 user_id uuid references auth.users on delete cascade, request_id uuid not null,
 item_id text references public.store_items, days integer not null, cost integer not null,
 primary key(user_id,request_id)
);
alter table public.store_items enable row level security;
alter table public.store_inventory enable row level security;
alter table public.store_receipts enable row level security;
revoke all on public.store_items,public.store_inventory,public.store_receipts from public,anon,authenticated;
grant select on public.store_items,public.store_inventory to authenticated;
create policy catalog_read on public.store_items for select to authenticated using(true);
create policy own_inventory on public.store_inventory for select to authenticated using(user_id=auth.uid());
create function public.buy_store_item(p_item text,p_days integer,p_request uuid) returns void
language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); price integer; bal integer; prior public.store_receipts; inv public.store_inventory;
begin
 if u is null or p_request is null then raise exception 'Sign in to purchase'; end if;
 select balance into strict bal from public.wallets where user_id=u for update;
 select * into prior from public.store_receipts where user_id=u and request_id=p_request;
 if found then
   if prior.item_id<>p_item or prior.days<>p_days then raise exception 'Purchase request conflict'; end if;
   return;
 end if;
 select prices[array_position(array[1,3,7,0],p_days)] into price from public.store_items where id=p_item;
 if price is null then raise exception 'Invalid item or duration'; end if;
 select * into inv from public.store_inventory where user_id=u and item_id=p_item;
 if found and inv.expires_at is null then raise exception 'Already owned permanently'; end if;
 if bal<price then raise exception 'Insufficient credits'; end if;
 insert into public.store_receipts values(u,p_request,p_item,p_days,price);
 update public.wallets set balance=balance-price,updated_at=now() where user_id=u;
 insert into public.wallet_transactions(user_id,amount,transaction_type,description)
 values(u,-price,'adjustment','Store purchase: '||p_item);
 insert into public.store_inventory(user_id,item_id,expires_at)
 values(u,p_item,case when p_days>0 then greatest(now(),inv.expires_at)+make_interval(days=>p_days) end)
 on conflict(user_id,item_id) do update set expires_at=excluded.expires_at,
 equipped=public.store_inventory.equipped and public.store_inventory.expires_at>now();
end $$;
create function public.equip_store_item(p_item text,p_on boolean) returns void
language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); cat text;
begin
 perform 1 from public.wallets where user_id=u for update;
 select i.category into strict cat from public.store_items i join public.store_inventory o on o.item_id=i.id
 where o.user_id=u and i.id=p_item and (o.expires_at is null or o.expires_at>now());
 if p_on then update public.store_inventory set equipped=false where user_id=u and item_id in
 (select id from public.store_items where category=cat); end if;
 update public.store_inventory set equipped=p_on where user_id=u and item_id=p_item;
end $$;
revoke all on function public.buy_store_item(text,integer,uuid),public.equip_store_item(text,boolean) from public,anon;
grant execute on function public.buy_store_item(text,integer,uuid),public.equip_store_item(text,boolean) to authenticated;
