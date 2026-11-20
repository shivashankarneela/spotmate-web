create or replace function public.delete_my_spotmate_account() returns void
language plpgsql security definer set search_path='' as $$
declare actor uuid := auth.uid();
begin
 if actor is null then raise exception 'Sign in required'; end if;
 delete from auth.users where id=actor;
 if not found then raise exception 'Account unavailable'; end if;
end;
$$;
revoke all on function public.delete_my_spotmate_account() from public,anon;
grant execute on function public.delete_my_spotmate_account() to authenticated;
