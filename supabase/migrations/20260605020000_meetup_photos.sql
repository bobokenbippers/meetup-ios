-- ============================================================
-- Meetup Photos (run in Supabase SQL editor or via supabase db push)
-- ============================================================

-- Table: one row per uploaded photo
CREATE TABLE IF NOT EXISTS public.meetup_photos (
    id                uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    meetup_id         uuid        NOT NULL REFERENCES public.meetups(id) ON DELETE CASCADE,
    uploader_user_id  uuid        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    photo_url         text        NOT NULL,
    caption           text,
    created_at        timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS meetup_photos_meetup_idx   ON public.meetup_photos(meetup_id);
CREATE INDEX IF NOT EXISTS meetup_photos_uploader_idx ON public.meetup_photos(uploader_user_id);

-- Row-Level Security
ALTER TABLE public.meetup_photos ENABLE ROW LEVEL SECURITY;

-- Meetup participants can read photos from meetups they are part of
CREATE POLICY "participants can read meetup photos"
    ON public.meetup_photos
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.meetup_participants mp
            WHERE mp.meetup_id = meetup_photos.meetup_id
              AND mp.user_id   = auth.uid()
        )
    );

-- Meetup participants can upload photos (insert)
CREATE POLICY "participants can insert meetup photos"
    ON public.meetup_photos
    FOR INSERT
    WITH CHECK (
        uploader_user_id = auth.uid()
        AND EXISTS (
            SELECT 1 FROM public.meetup_participants mp
            WHERE mp.meetup_id = meetup_photos.meetup_id
              AND mp.user_id   = auth.uid()
        )
    );

-- Uploaders can delete their own photos
CREATE POLICY "uploaders can delete own photos"
    ON public.meetup_photos
    FOR DELETE
    USING (uploader_user_id = auth.uid());

-- ============================================================
-- Storage bucket: meetup-photos
-- ============================================================
-- NOTE: Create this bucket in Supabase Dashboard → Storage → New bucket
--   Bucket name:  meetup-photos
--   Public:       false  (use signed URLs)
--
-- Storage RLS policies (set in Dashboard → Storage → Policies → meetup-photos):
--
-- INSERT policy (authenticated participants can upload):
--   bucket_id = 'meetup-photos'
--   AND auth.uid() IS NOT NULL
--
-- SELECT / signed-URL policy (authenticated participants can read):
--   bucket_id = 'meetup-photos'
--   AND auth.uid() IS NOT NULL
--
-- Files are stored at path: <meetup_id>/<uuid>.jpg
-- Signed URLs expire in 3600 seconds (1 hour).
