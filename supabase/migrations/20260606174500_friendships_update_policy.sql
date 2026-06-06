CREATE POLICY "users can update friendships they're part of"
ON public.friendships FOR UPDATE
USING (auth.uid() = user_a_id OR auth.uid() = user_b_id);
