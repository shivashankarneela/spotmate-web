alter table public.messages
  add column reply_to uuid,
  add constraint messages_reply_in_conversation
    foreign key (reply_to, conversation_id)
    references public.messages (id, conversation_id)
    on delete set null (reply_to),
  add constraint messages_cannot_reply_to_self check (reply_to <> id);

create index messages_reply_to_idx on public.messages (reply_to, conversation_id)
  where reply_to is not null;
