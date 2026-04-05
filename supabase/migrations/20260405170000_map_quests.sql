-- MAP-1.1: Map Quest Engine
-- Tracks daily quest completions and awards Qarmet.
-- Quest definitions are hardcoded in Flutter (no DB table needed for definitions).

-- Quest pass flag on users (Quest Pass subscription)
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS quest_pass_active BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS quest_pass_expires_at TIMESTAMPTZ;

-- Daily quest completions
CREATE TABLE IF NOT EXISTS map_quest_completions (
  id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  quest_id        TEXT         NOT NULL,
  quest_date      DATE         NOT NULL DEFAULT (CURRENT_DATE AT TIME ZONE 'UTC'),
  qarmet_awarded  INTEGER      NOT NULL DEFAULT 0,
  completed_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- One completion per user per quest per day
CREATE UNIQUE INDEX IF NOT EXISTS idx_quest_completions_unique
  ON map_quest_completions (user_id, quest_id, quest_date);

-- Fast lookup of today's completions per user
CREATE INDEX IF NOT EXISTS idx_quest_completions_user_date
  ON map_quest_completions (user_id, quest_date DESC);

-- -----------------------------------------------------------------------
-- RPC: get_today_quest_progress
-- Returns completed quest IDs for the calling user today.
-- -----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_today_quest_progress()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id   UUID := auth.uid();
  v_today     DATE := CURRENT_DATE AT TIME ZONE 'UTC';
  v_rows      jsonb;
  v_pass      BOOLEAN;
  v_total     INTEGER;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('quest_pass', false, 'completions', '[]'::jsonb, 'total_today', 0);
  END IF;

  SELECT
    jsonb_agg(jsonb_build_object('quest_id', quest_id, 'qarmet', qarmet_awarded)),
    COALESCE(SUM(qarmet_awarded), 0)
  INTO v_rows, v_total
  FROM map_quest_completions
  WHERE user_id = v_user_id AND quest_date = v_today;

  SELECT quest_pass_active AND (quest_pass_expires_at IS NULL OR quest_pass_expires_at > NOW())
  INTO v_pass
  FROM users WHERE id = v_user_id;

  RETURN jsonb_build_object(
    'quest_pass',   COALESCE(v_pass, false),
    'completions',  COALESCE(v_rows, '[]'::jsonb),
    'total_today',  v_total
  );
END;
$$;

-- -----------------------------------------------------------------------
-- RPC: complete_map_quest
-- Marks quest as done and credits Qarmet if not already done today.
-- p_quest_id: 'open_map' | 'view_3_listings' | 'message_seller' |
--             'place_auction_bid' | 'share_location_friend'
-- Returns jsonb {success, already_done, qarmet_awarded, new_balance}
-- -----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION complete_map_quest(p_quest_id TEXT)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id      UUID    := auth.uid();
  v_today        DATE    := CURRENT_DATE AT TIME ZONE 'UTC';
  v_reward       INTEGER;
  v_pass_needed  BOOLEAN;
  v_has_pass     BOOLEAN;
  v_balance      INTEGER;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthenticated');
  END IF;

  -- Reward table
  v_reward := CASE p_quest_id
    WHEN 'open_map'            THEN 5
    WHEN 'view_3_listings'     THEN 10
    WHEN 'message_seller'      THEN 20
    WHEN 'place_auction_bid'   THEN 30
    WHEN 'share_location_friend' THEN 25
    ELSE NULL
  END;

  IF v_reward IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'unknown_quest');
  END IF;

  -- Quest Pass required for premium quests
  v_pass_needed := p_quest_id IN ('place_auction_bid', 'share_location_friend');
  IF v_pass_needed THEN
    SELECT quest_pass_active AND (quest_pass_expires_at IS NULL OR quest_pass_expires_at > NOW())
    INTO v_has_pass FROM users WHERE id = v_user_id;
    IF NOT COALESCE(v_has_pass, false) THEN
      RETURN jsonb_build_object('success', false, 'error', 'quest_pass_required');
    END IF;
  END IF;

  -- Insert (unique index prevents duplicates)
  BEGIN
    INSERT INTO map_quest_completions (user_id, quest_id, quest_date, qarmet_awarded)
    VALUES (v_user_id, p_quest_id, v_today, v_reward);
  EXCEPTION WHEN unique_violation THEN
    RETURN jsonb_build_object('success', true, 'already_done', true, 'qarmet_awarded', 0);
  END;

  -- Award Qarmet
  UPDATE users SET qarmet_balance = qarmet_balance + v_reward WHERE id = v_user_id
  RETURNING qarmet_balance INTO v_balance;

  RETURN jsonb_build_object(
    'success',        true,
    'already_done',   false,
    'qarmet_awarded', v_reward,
    'new_balance',    v_balance
  );
END;
$$;

COMMENT ON TABLE map_quest_completions IS
  'MAP-1.1: Daily quest completions. One row per user per quest per UTC day.';
