insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('my-photos', 'my-photos', false, 5242880,
  array['image/jpeg', 'image/png', 'image/webp']);

create table public.profile_photo_audiences (
  user_id uuid primary key references public.user_profiles(id) on delete cascade,
  audience text not null default 'connections'
    check (audience in ('everyone', 'connections', 'custom')),
  allowed_users uuid[] not null default '{}'
);

create table public.profile_gallery_photos (
  object_path text primary key,
  user_id uuid not null references public.user_profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  check (split_part(object_path, '/', 1) = user_id::text)
);

create index profile_gallery_photos_user_idx on public.profile_gallery_photos(user_id, created_at);

alter table public.profile_photo_audiences enable row level security;
alter table public.profile_gallery_photos enable row level security;

create function public.can_view_profile_gallery(p_owner uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and (
    auth.uid() = p_owner or (
      exists (select 1 from public.user_profiles where id = p_owner and is_active)
      and not exists (
        select 1 from public.user_blocks b
        where (b.blocker_id = p_owner and b.blocked_id = auth.uid())
           or (b.blocked_id = p_owner and b.blocker_id = auth.uid())
      )
      and (
        coalesce(a.audience, 'connections') = 'everyone'
        or (
          (coalesce(a.audience, 'connections') = 'connections'
            or (a.audience = 'custom' and auth.uid() = any(a.allowed_users)))
          and exists (
            select 1 from public.connections c
            where (c.user1_id = p_owner and c.user2_id = auth.uid())
               or (c.user2_id = p_owner and c.user1_id = auth.uid())
          )
        )
      )
    )
  )
  from (select 1) s left join public.profile_photo_audiences a on a.user_id = p_owner;
$$;

revoke all on function public.can_view_profile_gallery(uuid) from public, anon;
grant execute on function public.can_view_profile_gallery(uuid) to authenticated;

grant select, insert, update on public.profile_photo_audiences to authenticated;
grant select, insert on public.profile_gallery_photos to authenticated;

create policy "Owner reads gallery audience"
on public.profile_photo_audiences for select to authenticated using (user_id = auth.uid());
create policy "Owner sets initial gallery audience"
on public.profile_photo_audiences for insert to authenticated with check (user_id = auth.uid());
create policy "Owner changes gallery audience"
on public.profile_photo_audiences for update to authenticated
using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "Authorized gallery viewers see photo records"
on public.profile_gallery_photos for select to authenticated
using (public.can_view_profile_gallery(user_id));
create policy "Owner adds gallery photo records"
on public.profile_gallery_photos for insert to authenticated
with check (user_id = auth.uid());

-- Deny signing and copying even when another permissive storage policy matches.
create policy "Gallery objects require a permitted storage operation"
on storage.objects as restrictive for all to public
using (
  bucket_id <> 'my-photos'
  or (
    auth.uid() is not null and (
      storage.allow_any_operation(array['object.get_authenticated', 'object.get_authenticated_info'])
      and exists (
        select 1 from public.profile_gallery_photos p
        where p.object_path = storage.objects.name
      )
      or storage.allow_any_operation(array['object.delete', 'object.delete_many'])
      and (storage.foldername(name))[1] = auth.uid()::text
    )
  )
)
with check (
  bucket_id <> 'my-photos' or (
    storage.allow_only_operation('object.upload')
    and (storage.foldername(name))[1] = auth.uid()::text
  )
);

create policy "Authorized gallery viewers download registered photos"
on storage.objects for select to authenticated using (
  bucket_id = 'my-photos' and (
    (storage.foldername(name))[1] = auth.uid()::text or exists (
      select 1 from public.profile_gallery_photos p
      where p.object_path = storage.objects.name
    )
  )
);
create policy "Owner uploads gallery photos"
on storage.objects for insert to authenticated with check (
  bucket_id = 'my-photos' and (storage.foldername(name))[1] = auth.uid()::text
);
create policy "Owner removes gallery photo objects"
on storage.objects for delete to authenticated using (
  bucket_id = 'my-photos' and (storage.foldername(name))[1] = auth.uid()::text
);

grant delete on public.profile_gallery_photos to authenticated;
create policy "Owner removes gallery photo records"
on public.profile_gallery_photos for delete to authenticated using (user_id = auth.uid());
