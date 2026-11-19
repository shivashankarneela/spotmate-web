alter table public.hotspot_messages
  add column media_path text,
  add column media_kind text,
  add constraint hotspot_message_media_valid check (
    (media_path is null and media_kind is null) or
    (media_path is not null and media_kind is not null and
      split_part(media_path,'/',1)=hotspot_id::text and
      split_part(media_path,'/',2)=sender_id::text and
      split_part(media_path,'/',4)='' and
      ((media_kind='photo' and split_part(media_path,'/',3) ~ '^[0-9]+[.](jpeg|png|webp|gif)$') or
       (media_kind='voice' and split_part(media_path,'/',3) ~ '^[0-9]+[.]wav$')))
  );
create unique index hotspot_message_media_path_idx on public.hotspot_messages(media_path) where media_path is not null;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('room_media','room_media',false,5242880,array['image/jpeg','image/png','image/webp','image/gif','audio/wav'])
on conflict(id) do nothing;

create policy room_media_upload on storage.objects for insert to authenticated
with check (bucket_id='room_media' and (storage.foldername(name))[2]=(select auth.uid())::text
  and exists(select 1 from public.hotspots h
    where h.id::text=(storage.foldername(name))[1] and private.is_active_hotspot_member(h.id)));

create policy room_media_read on storage.objects for select to authenticated
using (bucket_id='room_media' and (
  (storage.foldername(name))[2]=(select auth.uid())::text or
  exists(select 1 from public.hotspot_messages m where m.media_path=objects.name and m.deleted_at is null)));

create policy room_media_cleanup_own on storage.objects for delete to authenticated
using (bucket_id='room_media' and (storage.foldername(name))[2]=(select auth.uid())::text
  and not exists(select 1 from public.hotspot_messages m where m.media_path=objects.name and m.deleted_at is null));
