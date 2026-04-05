-- MAP-3: District Leaderboard
-- Monthly activity score per user based on map interactions.
-- Score = quest completions * 1pt + bids placed * 5pt + zones purchased * 20pt + boost purchases * 3pt

CREATE OR REPLACE FUNCTION get_map_leaderboard(p_limit INTEGER DEFAULT 10)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rows jsonb;
  v_month_start DATE := date_trunc('month', NOW())::DATE;
BEGIN
  SELECT jsonb_agg(ranked)
  INTO v_rows
  FROM (
    SELECT
      u.id              AS user_id,
      u.name            AS user_name,
      u.avatar          AS user_avatar,
      (
        -- Quest completions this month
        COALESCE((
          SELECT COUNT(*) * 1
          FROM map_quest_completions q
          WHERE q.user_id = u.id AND q.quest_date >= v_month_start
        ), 0)
        +
        -- Bids placed this month (any amount)
        COALESCE((
          SELECT COUNT(*) * 5
          FROM map_featured_bids b
          WHERE b.user_id = u.id AND b.bid_date >= v_month_start
        ), 0)
        +
        -- Zones purchased this month
        COALESCE((
          SELECT COUNT(*) * 20
          FROM map_zones z
          WHERE z.owner_id = u.id AND z.created_at >= v_month_start
        ), 0)
        +
        -- Map boosts purchased this month (products with active boost created this month)
        COALESCE((
          SELECT COUNT(*) * 3
          FROM products p
          WHERE p.seller_id = u.id
            AND p.map_boost_level > 0
            AND p.map_boost_expires_at >= NOW()
        ), 0)
      )::INTEGER AS score
    FROM users u
    ORDER BY score DESC
    LIMIT p_limit
  ) ranked
  WHERE ranked.score > 0;

  RETURN COALESCE(v_rows, '[]'::jsonb);
END;
$$;

-- Friend leaderboard: same score, but filtered to mutual followers
CREATE OR REPLACE FUNCTION get_friend_map_leaderboard(p_limit INTEGER DEFAULT 20)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id    UUID := auth.uid();
  v_month_start DATE := date_trunc('month', NOW())::DATE;
  v_rows       jsonb;
BEGIN
  IF v_user_id IS NULL THEN RETURN '[]'::jsonb; END IF;

  SELECT jsonb_agg(ranked)
  INTO v_rows
  FROM (
    SELECT
      u.id     AS user_id,
      u.name   AS user_name,
      u.avatar AS user_avatar,
      (
        COALESCE((SELECT COUNT(*) * 1 FROM map_quest_completions q
                  WHERE q.user_id = u.id AND q.quest_date >= v_month_start), 0)
        + COALESCE((SELECT COUNT(*) * 5 FROM map_featured_bids b
                    WHERE b.user_id = u.id AND b.bid_date >= v_month_start), 0)
        + COALESCE((SELECT COUNT(*) * 20 FROM map_zones z
                    WHERE z.owner_id = u.id AND z.created_at >= v_month_start), 0)
        + COALESCE((SELECT COUNT(*) * 3 FROM products p
                    WHERE p.seller_id = u.id AND p.map_boost_level > 0
                      AND p.map_boost_expires_at >= NOW()), 0)
      )::INTEGER AS score,
      -- Is this the calling user?
      (u.id = v_user_id) AS is_me
    FROM users u
    WHERE u.id = v_user_id
      OR u.id IN (
        -- mutual followers (friends)
        SELECT f1.following_id
        FROM followers f1
        WHERE f1.follower_id = v_user_id
          AND EXISTS (
            SELECT 1 FROM followers f2
            WHERE f2.follower_id = f1.following_id AND f2.following_id = v_user_id
          )
      )
    ORDER BY score DESC
    LIMIT p_limit
  ) ranked;

  RETURN COALESCE(v_rows, '[]'::jsonb);
END;
$$;

COMMENT ON FUNCTION get_map_leaderboard IS
  'MAP-3: Monthly map activity leaderboard. Score = quests*1 + bids*5 + zones*20 + boosts*3.';
