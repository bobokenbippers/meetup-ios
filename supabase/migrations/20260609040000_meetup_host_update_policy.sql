-- Harden the meetups UPDATE policy so the host edit path (e.g. changing the
-- destination/address after creation) is fully covered, and a host cannot
-- reassign a meetup to another host_id on update.
--
-- The original policy (M3.1) only had a USING clause:
--   create policy "host can update meetups" on public.meetups for update
--     using (auth.uid() = host_id);
-- USING gates which rows the host may target; WITH CHECK validates the row's
-- post-update state. Adding WITH CHECK ensures the row still belongs to the
-- same host after the update.

drop policy if exists "host can update meetups" on public.meetups;

create policy "host can update meetups"
  on public.meetups for update
  using (auth.uid() = host_id)
  with check (auth.uid() = host_id);
