drop policy if exists "participants can delete receipts" on public.receipts;
create policy "participants can delete receipts"
  on public.receipts for delete
  using (exists (
    select 1
    from public.meetup_participants
    where meetup_participants.meetup_id = receipts.meetup_id
      and meetup_participants.user_id = auth.uid()
  ));
