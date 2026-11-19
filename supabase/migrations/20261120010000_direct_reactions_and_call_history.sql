alter table public.calls
  add column answered_at timestamptz,
  add column ended_at timestamptz,
  add column end_reason text check (end_reason in ('missed','cancelled','failed','completed'));

create index calls_conversation_history_idx on public.calls (conversation_id, created_at desc, id desc);

create function private.capture_call_history() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.status = 'accepted' and old.status = 'ringing' then
    new.answered_at := now();
  elsif new.status in ('ended','declined') and old.status in ('ringing','accepted') then
    new.ended_at := now();
  end if;
  return new;
end;
$$;

create trigger calls_capture_history before update of status on public.calls
for each row execute function private.capture_call_history();

alter table public.messages add constraint messages_id_conversation_id_key unique (id, conversation_id);

create table public.direct_message_reactions (
  message_id uuid not null,
  conversation_id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  reaction text check (reaction in ('👍','❤️','😂','😮','😢','🔥')),
  primary key (message_id, user_id),
  foreign key (message_id, conversation_id)
    references public.messages (id, conversation_id) on delete cascade
);
create index direct_message_reactions_conversation_idx on public.direct_message_reactions (conversation_id, message_id, user_id);
alter table public.direct_message_reactions enable row level security;
revoke all on public.direct_message_reactions from public, anon, authenticated;
grant select, insert on public.direct_message_reactions to authenticated;
grant update (message_id, conversation_id, user_id, reaction) on public.direct_message_reactions to authenticated;
create policy direct_reactions_read on public.direct_message_reactions for select to authenticated
using (private.is_conversation_member(conversation_id));
create policy direct_reactions_insert on public.direct_message_reactions for insert to authenticated
with check (user_id = (select auth.uid()) and private.is_conversation_member(conversation_id));
create policy direct_reactions_update on public.direct_message_reactions for update to authenticated
using (user_id = (select auth.uid()) and private.is_conversation_member(conversation_id))
with check (user_id = (select auth.uid()) and private.is_conversation_member(conversation_id));
create function private.keep_direct_reaction_identity() returns trigger
language plpgsql set search_path = '' as $
begin
  if (new.message_id, new.conversation_id, new.user_id) is distinct from
     (old.message_id, old.conversation_id, old.user_id) then
    raise exception 'Reaction identity cannot change';
  end if;
  return new;
end;
$;
create trigger direct_reaction_identity before update on public.direct_message_reactions
for each row execute function private.keep_direct_reaction_identity();
alter publication supabase_realtime add table public.direct_message_reactions;
