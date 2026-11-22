alter policy room_media_upload on storage.objects
with check (
  bucket_id = 'room_media'
  and (storage.foldername(name))[2] = (select auth.uid())::text
  and exists (
    select 1 from public.hotspots h
    where h.id::text = (storage.foldername(objects.name))[1]
      and private.is_active_hotspot_member(h.id)
  )
);
