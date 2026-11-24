create table private.profile_username_changes (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.user_profiles(id) on delete cascade,
  changed_at timestamptz not null default clock_timestamp()
);
create index profile_username_changes_recent on private.profile_username_changes(user_id, changed_at);

create function private.enforce_profile_edit_requirements()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  oldest_change timestamptz;
  change_count integer;
begin
  if new.username is not null and new.date_of_birth is not null and new.city_id is not null
     and char_length(btrim(coalesce(new.bio, ''))) < 50 then
    raise exception 'Write at least 50 characters about yourself.';
  end if;
  if tg_op = 'UPDATE' and old.username is not null
     and new.username is distinct from old.username then
    if new.username is null then raise exception 'A username is required'; end if;
    select count(*), min(changed_at) into change_count, oldest_change
    from private.profile_username_changes
    where user_id = new.id and changed_at > clock_timestamp() - interval '30 days';
    if change_count >= 2 then
      raise exception 'You have used both username changes. Next change available on % (UTC).',
        to_char((oldest_change + interval '30 days') at time zone 'UTC', 'YYYY-MM-DD HH24:MI');
    end if;
    insert into private.profile_username_changes(user_id) values (new.id);
  end if;
  return new;
end;
$$;

create trigger enforce_profile_edit_requirements
before insert or update of username, bio on public.user_profiles
for each row execute function private.enforce_profile_edit_requirements();

revoke all on function private.enforce_profile_edit_requirements() from public, anon, authenticated;
