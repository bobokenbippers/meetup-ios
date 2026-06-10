-- ============================================================
-- Edit Direct Messages
-- Sender-only body/caption edits with an edited_at timestamp.
-- ============================================================

alter table public.messages
  add column if not exists edited_at timestamptz;

drop policy if exists "senders update their own messages" on public.messages;
create policy "senders update their own messages"
  on public.messages for update
  using (
    sender_id = auth.uid()
    and public.can_message_conversation(conversation_id)
  )
  with check (
    sender_id = auth.uid()
    and public.can_message_conversation(conversation_id)
    and (body is not null or image_path is not null)
  );
