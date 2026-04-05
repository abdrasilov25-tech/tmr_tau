-- ============================================================
-- MAP GAMIFICATION — полный скрипт для Supabase SQL Editor
-- Запускай целиком: нажми "Run" один раз
-- ============================================================

-- ============================================================
-- ЧАСТЬ 1: MAP BOOST (MAP-2.1)
-- ============================================================

ALTER TABLE products
  ADD COLUMN IF NOT EXISTS map_boost_level   INTEGER      NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS map_boost_expires_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_products_map_boost
  ON products (map_boost_level, map_boost_expires_at)
  WHERE map_boost_level > 0;

CREATE OR REPLACE FUNCTION purchase_map_boost(
  p_product_id   UUID,
  p_boost_level  INTEGER,
  p_duration_hours INTEGER
) RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_user_id           UUID := auth.uid();
  v_cost              INTEGER;
  v_current_balance   INTEGER;
  v_product_seller_id UUID;
BEGIN
  IF p_boost_level NOT IN (1, 2) THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_level');
  END IF;
  IF p_duration_hours NOT IN (24, 72, 168) THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_duration');
  END IF;
  SELECT seller_id INTO v_product_seller_id FROM products WHERE id = p_product_id;
  IF v_product_seller_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'product_not_found');
  END IF;
  IF v_product_seller_id <> v_user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_owner');
  END IF;
  v_cost := CASE p_boost_level
    WHEN 1 THEN 50  * (p_duration_hours / 24)
    WHEN 2 THEN 150 * (p_duration_hours / 24)
  END;
  SELECT qarmet_balance INTO v_current_balance FROM users WHERE id = v_user_id;
  IF v_current_balance IS NULL OR v_current_balance < v_cost THEN
    RETURN jsonb_build_object(
      'success', false, 'error', 'insufficient_balance',
      'required', v_cost, 'balance', COALESCE(v_current_balance, 0)
    );
  END IF;
  UPDATE users SET qarmet_balance = qarmet_balance - v_cost WHERE id = v_user_id;
  UPDATE products
  SET
    map_boost_level      = p_boost_level,
    map_boost_expires_at = GREATEST(COALESCE(map_boost_expires_at, NOW()), NOW())
                           + (p_duration_hours || ' hours')::INTERVAL
  WHERE id = p_product_id;
  RETURN jsonb_build_object(
    'success', true, 'cost', v_cost, 'new_balance', v_current_balance - v_cost
  );
END;
$$;

-- ============================================================
-- ЧАСТЬ 2: FEATURED SELLER AUCTION (MAP-2.2)
-- ============================================================

CREATE TABLE IF NOT EXISTS map_featured_bids (
  id           UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  bid_amount   INTEGER      NOT NULL CHECK (bid_amount >= 200),
  bid_date     DATE         NOT NULL DEFAULT (CURRENT_DATE AT TIME ZONE 'UTC'),
  created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_featured_bids_user_date
  ON map_featured_bids (user_id, bid_date);
CREATE INDEX IF NOT EXISTS idx_featured_bids_date_amount
  ON map_featured_bids (bid_date DESC, bid_amount DESC);

CREATE OR REPLACE FUNCTION get_today_featured()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_today DATE := CURRENT_DATE AT TIME ZONE 'UTC';
  v_row   RECORD;
BEGIN
  SELECT b.user_id, b.bid_amount, u.name AS seller_name, u.avatar AS seller_avatar
  INTO v_row
  FROM map_featured_bids b JOIN users u ON u.id = b.user_id
  WHERE b.bid_date = v_today ORDER BY b.bid_amount DESC LIMIT 1;
  IF v_row IS NULL THEN RETURN jsonb_build_object('found', false); END IF;
  RETURN jsonb_build_object(
    'found', true, 'user_id', v_row.user_id,
    'bid_amount', v_row.bid_amount,
    'seller_name', v_row.seller_name, 'seller_avatar', v_row.seller_avatar
  );
END;
$$;

CREATE OR REPLACE FUNCTION place_featured_bid(p_bid_amount INTEGER)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user_id     UUID    := auth.uid();
  v_today       DATE    := CURRENT_DATE AT TIME ZONE 'UTC';
  v_balance     INTEGER;
  v_top_bid     INTEGER := 0;
  v_top_user    UUID;
  v_my_prev_bid INTEGER := 0;
  v_cost        INTEGER;
  v_min_required INTEGER;
  v_refund      INTEGER;
BEGIN
  IF v_user_id IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'unauthenticated'); END IF;
  SELECT bid_amount, user_id INTO v_top_bid, v_top_user
  FROM map_featured_bids WHERE bid_date = v_today ORDER BY bid_amount DESC LIMIT 1;
  v_top_bid := COALESCE(v_top_bid, 0);
  SELECT bid_amount INTO v_my_prev_bid
  FROM map_featured_bids WHERE user_id = v_user_id AND bid_date = v_today;
  v_my_prev_bid := COALESCE(v_my_prev_bid, 0);
  v_min_required := GREATEST(200, v_top_bid + 50);
  IF v_top_user = v_user_id THEN v_min_required := v_my_prev_bid + 1; END IF;
  IF p_bid_amount < v_min_required THEN
    RETURN jsonb_build_object('success', false, 'error', 'bid_too_low',
      'min_required', v_min_required, 'top_bid', v_top_bid);
  END IF;
  v_cost := p_bid_amount - v_my_prev_bid;
  SELECT qarmet_balance INTO v_balance FROM users WHERE id = v_user_id;
  IF v_balance < v_cost THEN
    RETURN jsonb_build_object('success', false, 'error', 'insufficient_balance',
      'required', v_cost, 'balance', v_balance);
  END IF;
  UPDATE users SET qarmet_balance = qarmet_balance - v_cost WHERE id = v_user_id;
  IF v_top_user IS NOT NULL AND v_top_user <> v_user_id AND v_top_bid > 0 THEN
    v_refund := (v_top_bid * 80) / 100;
    UPDATE users SET qarmet_balance = qarmet_balance + v_refund WHERE id = v_top_user;
  END IF;
  INSERT INTO map_featured_bids (user_id, bid_amount, bid_date)
  VALUES (v_user_id, p_bid_amount, v_today)
  ON CONFLICT (user_id, bid_date)
  DO UPDATE SET bid_amount = EXCLUDED.bid_amount, updated_at = NOW();
  RETURN jsonb_build_object('success', true, 'bid_amount', p_bid_amount,
    'new_balance', v_balance - v_cost, 'top_bid', p_bid_amount);
END;
$$;

-- ============================================================
-- ЧАСТЬ 3: QUEST ENGINE (MAP-1.1)
-- ============================================================

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS quest_pass_active BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS quest_pass_expires_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS map_quest_completions (
  id             UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  quest_id       TEXT         NOT NULL,
  quest_date     DATE         NOT NULL DEFAULT (CURRENT_DATE AT TIME ZONE 'UTC'),
  qarmet_awarded INTEGER      NOT NULL DEFAULT 0,
  completed_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_quest_completions_unique
  ON map_quest_completions (user_id, quest_id, quest_date);
CREATE INDEX IF NOT EXISTS idx_quest_completions_user_date
  ON map_quest_completions (user_id, quest_date DESC);

CREATE OR REPLACE FUNCTION get_today_quest_progress()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_today   DATE := CURRENT_DATE AT TIME ZONE 'UTC';
  v_rows    jsonb;
  v_pass    BOOLEAN;
  v_total   INTEGER;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('quest_pass', false, 'completions', '[]'::jsonb, 'total_today', 0);
  END IF;
  SELECT jsonb_agg(jsonb_build_object('quest_id', quest_id, 'qarmet', qarmet_awarded)),
         COALESCE(SUM(qarmet_awarded), 0)
  INTO v_rows, v_total
  FROM map_quest_completions WHERE user_id = v_user_id AND quest_date = v_today;
  SELECT quest_pass_active AND (quest_pass_expires_at IS NULL OR quest_pass_expires_at > NOW())
  INTO v_pass FROM users WHERE id = v_user_id;
  RETURN jsonb_build_object(
    'quest_pass', COALESCE(v_pass, false),
    'completions', COALESCE(v_rows, '[]'::jsonb),
    'total_today', v_total
  );
END;
$$;

CREATE OR REPLACE FUNCTION complete_map_quest(p_quest_id TEXT)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user_id     UUID    := auth.uid();
  v_today       DATE    := CURRENT_DATE AT TIME ZONE 'UTC';
  v_reward      INTEGER;
  v_pass_needed BOOLEAN;
  v_has_pass    BOOLEAN;
  v_balance     INTEGER;
BEGIN
  IF v_user_id IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'unauthenticated'); END IF;
  v_reward := CASE p_quest_id
    WHEN 'open_map'              THEN 5
    WHEN 'view_3_listings'       THEN 10
    WHEN 'message_seller'        THEN 20
    WHEN 'place_auction_bid'     THEN 30
    WHEN 'share_location_friend' THEN 25
    ELSE NULL
  END;
  IF v_reward IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'unknown_quest'); END IF;
  v_pass_needed := p_quest_id IN ('place_auction_bid', 'share_location_friend');
  IF v_pass_needed THEN
    SELECT quest_pass_active AND (quest_pass_expires_at IS NULL OR quest_pass_expires_at > NOW())
    INTO v_has_pass FROM users WHERE id = v_user_id;
    IF NOT COALESCE(v_has_pass, false) THEN
      RETURN jsonb_build_object('success', false, 'error', 'quest_pass_required');
    END IF;
  END IF;
  BEGIN
    INSERT INTO map_quest_completions (user_id, quest_id, quest_date, qarmet_awarded)
    VALUES (v_user_id, p_quest_id, v_today, v_reward);
  EXCEPTION WHEN unique_violation THEN
    RETURN jsonb_build_object('success', true, 'already_done', true, 'qarmet_awarded', 0);
  END;
  UPDATE users SET qarmet_balance = qarmet_balance + v_reward WHERE id = v_user_id
  RETURNING qarmet_balance INTO v_balance;
  RETURN jsonb_build_object('success', true, 'already_done', false,
    'qarmet_awarded', v_reward, 'new_balance', v_balance);
END;
$$;

-- ============================================================
-- ЧАСТЬ 4: ZONE TAKEOVER (MAP-4)
-- ============================================================

CREATE TABLE IF NOT EXISTS map_zones (
  id             UUID             PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id       UUID             NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name           TEXT             NOT NULL,
  description    TEXT,
  offer_text     TEXT,
  brand_color    TEXT             NOT NULL DEFAULT '#2563EB',
  latitude       DOUBLE PRECISION NOT NULL,
  longitude      DOUBLE PRECISION NOT NULL,
  radius_meters  INTEGER          NOT NULL DEFAULT 500 CHECK (radius_meters IN (500, 1000)),
  active_until   TIMESTAMPTZ      NOT NULL,
  created_at     TIMESTAMPTZ      NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_map_zones_active ON map_zones (active_until DESC) WHERE active_until > NOW();
CREATE INDEX IF NOT EXISTS idx_map_zones_owner  ON map_zones (owner_id);

CREATE OR REPLACE FUNCTION get_active_zones()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rows jsonb;
BEGIN
  SELECT jsonb_agg(jsonb_build_object(
    'id', z.id, 'owner_id', z.owner_id, 'name', z.name,
    'description', z.description, 'offer_text', z.offer_text,
    'brand_color', z.brand_color, 'latitude', z.latitude,
    'longitude', z.longitude, 'radius_meters', z.radius_meters,
    'active_until', z.active_until, 'owner_avatar', u.avatar
  )) INTO v_rows
  FROM map_zones z JOIN users u ON u.id = z.owner_id WHERE z.active_until > NOW();
  RETURN COALESCE(v_rows, '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION purchase_map_zone(
  p_name TEXT, p_description TEXT, p_offer_text TEXT, p_brand_color TEXT,
  p_latitude DOUBLE PRECISION, p_longitude DOUBLE PRECISION,
  p_radius_meters INTEGER, p_duration_days INTEGER
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user_id UUID    := auth.uid();
  v_cost    INTEGER;
  v_balance INTEGER;
  v_zone_id UUID;
BEGIN
  IF v_user_id IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'unauthenticated'); END IF;
  IF p_radius_meters NOT IN (500, 1000) THEN RETURN jsonb_build_object('success', false, 'error', 'invalid_radius'); END IF;
  IF p_duration_days NOT IN (7, 30) THEN RETURN jsonb_build_object('success', false, 'error', 'invalid_duration'); END IF;
  v_cost := CASE
    WHEN p_radius_meters = 500  AND p_duration_days = 7  THEN 2000
    WHEN p_radius_meters = 500  AND p_duration_days = 30 THEN 6000
    WHEN p_radius_meters = 1000 AND p_duration_days = 7  THEN 4000
    WHEN p_radius_meters = 1000 AND p_duration_days = 30 THEN 12000
    ELSE 2000
  END;
  SELECT qarmet_balance INTO v_balance FROM users WHERE id = v_user_id;
  IF v_balance < v_cost THEN
    RETURN jsonb_build_object('success', false, 'error', 'insufficient_balance',
      'required', v_cost, 'balance', v_balance);
  END IF;
  UPDATE users SET qarmet_balance = qarmet_balance - v_cost WHERE id = v_user_id;
  INSERT INTO map_zones (owner_id, name, description, offer_text, brand_color,
    latitude, longitude, radius_meters, active_until)
  VALUES (v_user_id, p_name, p_description, p_offer_text, p_brand_color,
    p_latitude, p_longitude, p_radius_meters, NOW() + (p_duration_days || ' days')::INTERVAL)
  RETURNING id INTO v_zone_id;
  RETURN jsonb_build_object('success', true, 'zone_id', v_zone_id,
    'cost', v_cost, 'new_balance', v_balance - v_cost);
END;
$$;

-- ============================================================
-- ЧАСТЬ 5: STICKER PACKS (MAP-5)
-- ============================================================

ALTER TABLE products
  ADD COLUMN IF NOT EXISTS map_marker_sticker TEXT;

CREATE TABLE IF NOT EXISTS map_sticker_packs (
  user_id      UUID  NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  pack_id      TEXT  NOT NULL,
  purchased_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY  (user_id, pack_id)
);

CREATE OR REPLACE FUNCTION get_my_sticker_packs()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user_id UUID := auth.uid(); v_packs jsonb;
BEGIN
  IF v_user_id IS NULL THEN RETURN '[]'::jsonb; END IF;
  SELECT jsonb_agg(pack_id) INTO v_packs FROM map_sticker_packs WHERE user_id = v_user_id;
  RETURN COALESCE(v_packs, '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION purchase_sticker_pack(p_pack_id TEXT)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user_id UUID := auth.uid(); v_cost INTEGER := 500; v_balance INTEGER;
BEGIN
  IF v_user_id IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'unauthenticated'); END IF;
  IF p_pack_id NOT IN ('animals', 'kazakhstan', 'seasonal_newyear') THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_pack');
  END IF;
  IF EXISTS (SELECT 1 FROM map_sticker_packs WHERE user_id = v_user_id AND pack_id = p_pack_id) THEN
    SELECT qarmet_balance INTO v_balance FROM users WHERE id = v_user_id;
    RETURN jsonb_build_object('success', true, 'already_owned', true, 'new_balance', v_balance);
  END IF;
  SELECT qarmet_balance INTO v_balance FROM users WHERE id = v_user_id;
  IF v_balance < v_cost THEN
    RETURN jsonb_build_object('success', false, 'error', 'insufficient_balance',
      'required', v_cost, 'balance', v_balance);
  END IF;
  UPDATE users SET qarmet_balance = qarmet_balance - v_cost WHERE id = v_user_id;
  INSERT INTO map_sticker_packs (user_id, pack_id) VALUES (v_user_id, p_pack_id);
  RETURN jsonb_build_object('success', true, 'already_owned', false, 'new_balance', v_balance - v_cost);
END;
$$;

CREATE OR REPLACE FUNCTION set_product_marker_sticker(p_product_id UUID, p_sticker TEXT)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user_id UUID := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'unauthenticated'); END IF;
  UPDATE products SET map_marker_sticker = p_sticker
  WHERE id = p_product_id AND seller_id = v_user_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'not_owner'); END IF;
  RETURN jsonb_build_object('success', true);
END;
$$;

-- ============================================================
-- ЧАСТЬ 6: LEADERBOARD (MAP-3)
-- ============================================================

CREATE OR REPLACE FUNCTION get_map_leaderboard(p_limit INTEGER DEFAULT 10)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rows jsonb; v_month_start DATE := date_trunc('month', NOW())::DATE;
BEGIN
  SELECT jsonb_agg(ranked) INTO v_rows FROM (
    SELECT u.id AS user_id, u.name AS user_name, u.avatar AS user_avatar,
      (COALESCE((SELECT COUNT(*) * 1 FROM map_quest_completions q
                 WHERE q.user_id = u.id AND q.quest_date >= v_month_start), 0)
       + COALESCE((SELECT COUNT(*) * 5 FROM map_featured_bids b
                   WHERE b.user_id = u.id AND b.bid_date >= v_month_start), 0)
       + COALESCE((SELECT COUNT(*) * 20 FROM map_zones z
                   WHERE z.owner_id = u.id AND z.created_at >= v_month_start), 0)
       + COALESCE((SELECT COUNT(*) * 3 FROM products p
                   WHERE p.seller_id = u.id AND p.map_boost_level > 0
                     AND p.map_boost_expires_at >= NOW()), 0)
      )::INTEGER AS score
    FROM users u ORDER BY score DESC LIMIT p_limit
  ) ranked WHERE ranked.score > 0;
  RETURN COALESCE(v_rows, '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION get_friend_map_leaderboard(p_limit INTEGER DEFAULT 20)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user_id    UUID := auth.uid();
  v_month_start DATE := date_trunc('month', NOW())::DATE;
  v_rows       jsonb;
BEGIN
  IF v_user_id IS NULL THEN RETURN '[]'::jsonb; END IF;
  SELECT jsonb_agg(ranked) INTO v_rows FROM (
    SELECT u.id AS user_id, u.name AS user_name, u.avatar AS user_avatar,
      (COALESCE((SELECT COUNT(*) * 1 FROM map_quest_completions q
                 WHERE q.user_id = u.id AND q.quest_date >= v_month_start), 0)
       + COALESCE((SELECT COUNT(*) * 5 FROM map_featured_bids b
                   WHERE b.user_id = u.id AND b.bid_date >= v_month_start), 0)
       + COALESCE((SELECT COUNT(*) * 20 FROM map_zones z
                   WHERE z.owner_id = u.id AND z.created_at >= v_month_start), 0)
       + COALESCE((SELECT COUNT(*) * 3 FROM products p
                   WHERE p.seller_id = u.id AND p.map_boost_level > 0
                     AND p.map_boost_expires_at >= NOW()), 0)
      )::INTEGER AS score,
      (u.id = v_user_id) AS is_me
    FROM users u
    WHERE u.id = v_user_id OR u.id IN (
      SELECT f1.following_id FROM followers f1
      WHERE f1.follower_id = v_user_id
        AND EXISTS (SELECT 1 FROM followers f2
                    WHERE f2.follower_id = f1.following_id AND f2.following_id = v_user_id)
    )
    ORDER BY score DESC LIMIT p_limit
  ) ranked;
  RETURN COALESCE(v_rows, '[]'::jsonb);
END;
$$;

-- ============================================================
-- ЧАСТЬ 7: MYSTERY SPOT (MAP-6)
-- ============================================================

CREATE TABLE IF NOT EXISTS map_mystery_spots (
  id                  UUID             PRIMARY KEY DEFAULT gen_random_uuid(),
  spot_date           DATE             NOT NULL DEFAULT (CURRENT_DATE AT TIME ZONE 'UTC'),
  latitude            DOUBLE PRECISION NOT NULL,
  longitude           DOUBLE PRECISION NOT NULL,
  is_seller_sponsored BOOLEAN          NOT NULL DEFAULT FALSE,
  seller_id           UUID             REFERENCES users(id) ON DELETE SET NULL,
  seller_offer        TEXT,
  product_id          UUID             REFERENCES products(id) ON DELETE SET NULL,
  qarmet_reward       INTEGER          NOT NULL DEFAULT 20,
  created_at          TIMESTAMPTZ      NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_mystery_spots_date ON map_mystery_spots (spot_date DESC);

CREATE TABLE IF NOT EXISTS map_mystery_spot_claims (
  spot_id    UUID NOT NULL REFERENCES map_mystery_spots(id) ON DELETE CASCADE,
  user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  claimed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (spot_id, user_id)
);

CREATE OR REPLACE FUNCTION get_today_mystery_spot(
  p_lat DOUBLE PRECISION, p_lng DOUBLE PRECISION
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_today   DATE := CURRENT_DATE AT TIME ZONE 'UTC';
  v_spot    RECORD;
  v_claimed BOOLEAN;
  v_lat_off DOUBLE PRECISION;
  v_lng_off DOUBLE PRECISION;
BEGIN
  SELECT s.*, u.name AS seller_name, u.avatar AS seller_avatar
  INTO v_spot FROM map_mystery_spots s LEFT JOIN users u ON u.id = s.seller_id
  WHERE s.spot_date = v_today ORDER BY s.is_seller_sponsored DESC, s.created_at ASC LIMIT 1;
  IF v_spot IS NULL THEN
    v_lat_off := (random() * 0.08) - 0.04;
    v_lng_off := (random() * 0.08) - 0.04;
    INSERT INTO map_mystery_spots (spot_date, latitude, longitude, qarmet_reward)
    VALUES (v_today, p_lat + v_lat_off, p_lng + v_lng_off, 20) RETURNING * INTO v_spot;
  END IF;
  SELECT EXISTS (SELECT 1 FROM map_mystery_spot_claims
    WHERE spot_id = v_spot.id AND user_id = v_user_id) INTO v_claimed;
  RETURN jsonb_build_object(
    'id', v_spot.id, 'latitude', v_spot.latitude, 'longitude', v_spot.longitude,
    'is_seller_sponsored', v_spot.is_seller_sponsored,
    'seller_name', v_spot.seller_name, 'seller_offer', v_spot.seller_offer,
    'seller_id', v_spot.seller_id, 'product_id', v_spot.product_id,
    'qarmet_reward', v_spot.qarmet_reward, 'already_claimed', COALESCE(v_claimed, false)
  );
END;
$$;

CREATE OR REPLACE FUNCTION reveal_mystery_spot(p_spot_id UUID)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user_id UUID    := auth.uid();
  v_balance INTEGER;
  v_spot    RECORD;
BEGIN
  IF v_user_id IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'unauthenticated'); END IF;
  SELECT * INTO v_spot FROM map_mystery_spots WHERE id = p_spot_id;
  IF v_spot IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'not_found'); END IF;
  BEGIN
    INSERT INTO map_mystery_spot_claims (spot_id, user_id) VALUES (p_spot_id, v_user_id);
  EXCEPTION WHEN unique_violation THEN
    SELECT qarmet_balance INTO v_balance FROM users WHERE id = v_user_id;
    RETURN jsonb_build_object('success', true, 'already_claimed', true,
      'qarmet_awarded', 0, 'new_balance', v_balance);
  END;
  UPDATE users SET qarmet_balance = qarmet_balance + v_spot.qarmet_reward
  WHERE id = v_user_id RETURNING qarmet_balance INTO v_balance;
  RETURN jsonb_build_object(
    'success', true, 'already_claimed', false,
    'qarmet_awarded', v_spot.qarmet_reward, 'new_balance', v_balance,
    'is_seller_sponsored', v_spot.is_seller_sponsored,
    'seller_offer', v_spot.seller_offer, 'product_id', v_spot.product_id
  );
END;
$$;

CREATE OR REPLACE FUNCTION purchase_mystery_spot_slot(
  p_offer_text TEXT, p_product_id UUID, p_bid_amount INTEGER
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user_id   UUID    := auth.uid();
  v_tomorrow  DATE    := (CURRENT_DATE AT TIME ZONE 'UTC') + 1;
  v_balance   INTEGER;
  v_spot_id   UUID;
  v_prod_lat  DOUBLE PRECISION;
  v_prod_lng  DOUBLE PRECISION;
BEGIN
  IF v_user_id IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'unauthenticated'); END IF;
  IF p_bid_amount < 200 THEN RETURN jsonb_build_object('success', false, 'error', 'bid_too_low', 'min', 200); END IF;
  IF EXISTS (SELECT 1 FROM map_mystery_spots WHERE spot_date = v_tomorrow AND is_seller_sponsored = TRUE) THEN
    RETURN jsonb_build_object('success', false, 'error', 'slot_taken');
  END IF;
  SELECT qarmet_balance INTO v_balance FROM users WHERE id = v_user_id;
  IF v_balance < p_bid_amount THEN
    RETURN jsonb_build_object('success', false, 'error', 'insufficient_balance',
      'required', p_bid_amount, 'balance', v_balance);
  END IF;
  SELECT latitude, longitude INTO v_prod_lat, v_prod_lng
  FROM products WHERE id = p_product_id AND seller_id = v_user_id;
  IF v_prod_lat IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'product_not_found'); END IF;
  UPDATE users SET qarmet_balance = qarmet_balance - p_bid_amount WHERE id = v_user_id;
  INSERT INTO map_mystery_spots (spot_date, latitude, longitude, is_seller_sponsored,
    seller_id, seller_offer, product_id, qarmet_reward)
  VALUES (v_tomorrow,
    v_prod_lat + (random() * 0.004 - 0.002),
    v_prod_lng + (random() * 0.004 - 0.002),
    TRUE, v_user_id, p_offer_text, p_product_id,
    GREATEST(10, (p_bid_amount * 15) / 100))
  RETURNING id INTO v_spot_id;
  RETURN jsonb_build_object('success', true, 'spot_id', v_spot_id,
    'new_balance', v_balance - p_bid_amount, 'spot_date', v_tomorrow::TEXT);
END;
$$;

-- ============================================================
-- ГОТОВО — все 7 фич подключены
-- ============================================================
SELECT 'Map Gamification SQL applied successfully!' AS status;
