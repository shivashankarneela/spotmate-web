-- HaloBerry 100-illustration avatar release.
-- Existing member photos remain untouched. Only illustrated avatars with an
-- explicitly recorded Male/Female gender are assigned matching default art.
-- Users with other/unset gender retain their choice: we never infer identity.
alter table public.user_profiles
  add column if not exists avatar_posture_index smallint not null default 0;
alter table public.user_profiles
  add column if not exists avatar_posture_auto boolean not null default false;

do $$ begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'user_profiles_avatar_posture_index_check'
       and conrelid = 'public.user_profiles'::regclass
  ) then
    alter table public.user_profiles
      add constraint user_profiles_avatar_posture_index_check
      check (avatar_posture_index between 0 and 4);
  end if;
end $$;

-- Deterministic variety across the ten available characters in each category.
-- Existing photo uploads are preserved, and this does not change profile gender.
update public.user_profiles p
set avatar_emoticon = (
    case lower(btrim(p.gender))
      when 'male' then 'boy_'
      when 'female' then 'girl_'
    end
    || lpad(((get_byte(decode(md5(p.id::text), 'hex'), 0) % 10) + 1)::text, 2, '0')
  )
where p.avatar_type = 'emoticon'
  and lower(btrim(p.gender)) in ('male', 'female')
  and p.avatar_emoticon is distinct from (
    case lower(btrim(p.gender))
      when 'male' then 'boy_'
      when 'female' then 'girl_'
    end
    || lpad(((get_byte(decode(md5(p.id::text), 'hex'), 0) % 10) + 1)::text, 2, '0')
  );
