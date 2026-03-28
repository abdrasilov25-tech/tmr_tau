-- ============================================================
-- Migration: add_recommendation_fields
-- Adds geo, category, engagement counters and user interests
-- for the personalized recommendation algorithm.
-- All changes are ADDITIVE (safe on existing data).
-- ============================================================

-- ── 1. New columns on posts ──────────────────────────────────

-- views_count: incremented by publication_feed_impressions trigger
ALTER TABLE public.posts
  ADD COLUMN IF NOT EXISTS views_count int NOT NULL DEFAULT 0;

-- saved_count: denormalized counter from post_saves (kept in sync below)
ALTER TABLE public.posts
  ADD COLUMN IF NOT EXISTS saved_count int NOT NULL DEFAULT 0;

-- category: free-text tag for interest matching (e.g. 'Электроника', 'Спорт')
ALTER TABLE public.posts
  ADD COLUMN IF NOT EXISTS category text NOT NULL DEFAULT '';

-- geo columns: optional, NULL means "no location"
ALTER TABLE public.posts
  ADD COLUMN IF NOT EXISTS latitude  double precision;
ALTER TABLE public.posts
  ADD COLUMN IF NOT EXISTS longitude double precision;

-- ── 2. New column on users ───────────────────────────────────

-- interests: array of category slugs the user is interested in
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS interests text[] NOT NULL DEFAULT '{}';

-- ── 3. Indexes ───────────────────────────────────────────────

-- Geo index (partial – only rows that have coordinates)
CREATE INDEX IF NOT EXISTS idx_posts_geo
  ON public.posts (latitude, longitude)
  WHERE latitude IS NOT NULL AND longitude IS NOT NULL;

-- Category index for interest-based filtering
CREATE INDEX IF NOT EXISTS idx_posts_category
  ON public.posts (category)
  WHERE category <> '';

-- ── 4. Backfill saved_count from existing post_saves rows ────

UPDATE public.posts p
SET saved_count = s.cnt
FROM (
  SELECT post_id, COUNT(*) AS cnt
  FROM public.post_saves
  GROUP BY post_id
) s
WHERE s.post_id = p.id;

-- ── 5. Backfill views_count from existing impressions ────────

UPDATE public.posts p
SET views_count = v.cnt
FROM (
  SELECT post_id, COUNT(*) AS cnt
  FROM public.publication_feed_impressions
  GROUP BY post_id
) v
WHERE v.post_id = p.id;

-- ── 6. Trigger: keep saved_count in sync ─────────────────────

CREATE OR REPLACE FUNCTION public.sync_post_saved_count()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.posts
    SET saved_count = saved_count + 1
    WHERE id = NEW.post_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.posts
    SET saved_count = GREATEST(saved_count - 1, 0)
    WHERE id = OLD.post_id;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_post_saved_count ON public.post_saves;
CREATE TRIGGER trg_post_saved_count
  AFTER INSERT OR DELETE ON public.post_saves
  FOR EACH ROW EXECUTE FUNCTION public.sync_post_saved_count();

-- ── 7. Trigger: increment views_count on new impression ──────

CREATE OR REPLACE FUNCTION public.sync_post_views_count()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE public.posts
  SET views_count = views_count + 1
  WHERE id = NEW.post_id;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_post_views_count ON public.publication_feed_impressions;
CREATE TRIGGER trg_post_views_count
  AFTER INSERT ON public.publication_feed_impressions
  FOR EACH ROW EXECUTE FUNCTION public.sync_post_views_count();

-- ── 8. RLS: users can read interests of any public profile ───

-- posts columns inherit existing RLS on the posts table (no change needed).
-- users.interests: only owner can update their own interests.
-- (Read already allowed by existing "Users select" policy.)
DROP POLICY IF EXISTS "Users update interests" ON public.users;
CREATE POLICY "Users update interests"
  ON public.users
  FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);
