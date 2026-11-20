create table private.latest_login (
 user_id uuid primary key references auth.users on delete cascade, session_id uuid not null, signed_at timestamptz not null
);
revoke all on private.latest_login from public,anon,authenticated;
create function private.record_latest_login() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into private.latest_login values(new.user_id,new.id,new.created_at)
 on conflict(user_id) do update set session_id=excluded.session_id,signed_at=excluded.signed_at
 where (excluded.signed_at,excluded.session_id)>(private.latest_login.signed_at,private.latest_login.session_id);
 return new;
end $$;
revoke all on function private.record_latest_login() from public,anon,authenticated;
create trigger spotmate_latest_login after insert on auth.sessions for each row execute function private.record_latest_login();
insert into private.latest_login select distinct on(user_id) user_id,id,created_at from auth.sessions order by user_id,created_at desc,id desc
on conflict(user_id) do nothing;
create function public.spotmate_session_active() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select from private.latest_login l join auth.sessions s on s.id=l.session_id and s.user_id=l.user_id
 where l.user_id=auth.uid() and l.session_id=(auth.jwt()->>'session_id')::uuid)
$$;
revoke all on function public.spotmate_session_active() from public,anon;
grant execute on function public.spotmate_session_active() to authenticated;
create function public.spotmate_request_guard() returns void language plpgsql set search_path='' as $$
begin
 if current_user='authenticated' then
 if not public.spotmate_session_active() then
   raise sqlstate 'PT403' using message='SESSION_REPLACED';
 end if;
 end if;
end $$;
grant execute on function public.spotmate_request_guard() to anon,authenticated,service_role;
alter role authenticator set pgrst.db_pre_request='public.spotmate_request_guard';
notify pgrst,'reload config';
do $$ declare t record; begin
 for t in select n.nspname,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where c.relkind in ('r','p') and c.relrowsecurity and (n.nspname='public' or (n.nspname='storage' and c.relname='objects')
 or (n.nspname='realtime' and c.relname='messages'))
 loop execute format('create policy spotmate_current_login on %I.%I as restrictive for all to authenticated using ((select public.spotmate_session_active())) with check ((select public.spotmate_session_active()))',t.nspname,t.relname); end loop;
end $$;