-- Fix friend request inserts for canonical friendship rows.
--
-- Friendships store the smaller UUID in user_a_id and the larger UUID in
-- user_b_id. The old live INSERT policy only allowed auth.uid() = user_a_id,
-- so requests failed whenever the initiating user's UUID sorted second.

drop policy if exists "Users can create friendships" on public.friendships;
drop policy if exists "users can create friend requests they initiate" on public.friendships;

create policy "users can create friend requests they initiate"
  on public.friendships for insert
  with check (
    auth.uid() = initiated_by
    and (auth.uid() = user_a_id or auth.uid() = user_b_id)
    and status = 'pending'
  );
