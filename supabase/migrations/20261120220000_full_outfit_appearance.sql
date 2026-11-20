-- Keep existing costume IDs so purchases, receipts and expiry dates remain valid.
insert into public.store_items(id,title,category,prices) values
('indigo_denim','Indigo Mechanic','Costumes',array[2,4,7,20]),
('coastal_linen','Ivory Linen','Costumes',array[2,4,7,20]),
('emerald_stage','Emerald Bandhgala','Costumes',array[4,8,14,40]),
('terracotta_drape','Terracotta Dhoti Drape','Costumes',array[2,4,7,20]),
('navy_tuxedo','Midnight Tuxedo','Costumes',array[4,8,14,40]),
('monsoon_rider','Olive Flight Suit','Costumes',array[2,4,7,20]),
('solar_circuit','Cobalt Racing Suit','Costumes',array[4,8,14,40]),
('metro_runner','Onyx Techwear','Costumes',array[2,4,7,20]),
('sand_safari','Sand Safari','Costumes',array[2,4,7,20]),
('deccan_festive','Plum Brocade','Costumes',array[4,8,14,40]),
('denim_wrap','Indigo Wrap','Costumes',array[2,4,7,20]),
('saffron_anarkali','Saffron Anarkali','Costumes',array[2,4,7,20]),
('teal_scarf','Teal Sari Drape','Costumes',array[4,8,14,40]),
('varsity_club','Coral Shirt Dress','Costumes',array[2,4,7,20]),
('pearl_regent','Navy Tailored Jumpsuit','Costumes',array[4,8,14,40]),
('cocoa_knit','Lavender Pleats','Costumes',array[2,4,7,20]),
('court_club','Olive Utility','Costumes',array[2,4,7,20]),
('block_print_maxi','Cobalt Block Print','Costumes',array[2,4,7,20]),
('midnight_bloom','Burgundy Velvet','Costumes',array[4,8,14,40]),
('violet_dance','Violet Dance','Costumes',array[4,8,14,40])
on conflict(id) do update set title=excluded.title;

alter table public.store_inventory add column show_on_profile boolean not null default false;
update public.store_inventory o set show_on_profile=true from public.store_items i where i.id=o.item_id and i.category='Avatars' and o.equipped;
create function public.set_store_appearance(p_item text,p_on boolean,p_everywhere boolean)
returns void language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); cat text;
begin
 select category into strict cat from public.store_items where id=p_item and category in ('Costumes','Avatars');
 perform public.equip_store_item(p_item,p_on);
 if p_on and cat='Costumes' then
  update public.store_inventory o set equipped=false,show_on_profile=false from public.store_items i where o.item_id=i.id and i.category='Avatars' and o.user_id=u and o.equipped;
 end if;
 update public.store_inventory set show_on_profile=p_on and p_everywhere where user_id=u and item_id=p_item;
end $$;
revoke all on function public.set_store_appearance(text,boolean,boolean) from public,anon;
grant execute on function public.set_store_appearance(text,boolean,boolean) to authenticated;
create function public.profile_look(p public.user_profiles) returns text language sql stable security definer set search_path='' as $$
 select case when o.show_on_profile then o.item_id end from public.store_inventory o join public.store_items i on i.id=o.item_id where o.user_id=p.id and o.equipped and i.category in ('Avatars','Costumes') and (o.expires_at is null or o.expires_at>now()) order by (i.category='Avatars') desc limit 1
$$;
revoke all on function public.profile_look(public.user_profiles) from public,anon;
grant execute on function public.profile_look(public.user_profiles) to authenticated;
