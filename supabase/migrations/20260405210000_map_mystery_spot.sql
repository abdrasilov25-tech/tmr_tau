-- MAP-6: Mystery Spot
-- Daily hidden "?" marker on the map. Tap to reveal Qarmet or a seller offer.
-- Sellers pay 200 Qarmet to sponsor a spot for a day (guaranteed traffic).

-- Spots per day (system-generated or seller-sponsored)
CREATE TABLE IF NOT EXISTS map_mystery_spots (
  id                  UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  spot_date           DATE          NOT NULL DEFAULT (CURRENT_DATE AT TIME ZONE 'UTC'),
  latitude            DOUBLE PRECISION NOT NULL,
  longitude           DOUBLE PRECISION NOT NULL,
  is_seller_sponsored BOOLEAN       NOT NULL DEFAULT FALSE,
  seller_id           UUID          REFERENCES users(id) ON DELETE SET NULL,
  seller_offer        TEXT,
  product_id          UUID          REFERENCES products(id) ON DELETE SET NULL,
  qarmet_reward       INTEGER       NOT NULL DEFAULT 20,
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_mystery_spots_date
  ON map_mystery_spots (spot_date DESC);

-- Per-user claim tracking (each user can claim each spot once per day)
CREATE TABLE IF NOT EXISTS map_mystery_spot_claims (
  spot_id    UUID  NOT NULL REFERENCES map_mystery_spots(id) ON DELETE CASCADE,
  user_id    UUID  NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  claimed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (spot_id, user_id)
);

-- -----------------------------------------------------------------------
-- RPC: get_today_mystery_spot
-- Returns today's spot (seller-sponsored first, then system).
-- Creates a system spot lazily if none exists yet.
-- p_lat / p_lng: user's current position (for generating a nearby spot).
-- -----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_today_mystery_spot(
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id   UUID  := auth.uid();
  v_today     DATE  := CURRENT_DATE AT TIME ZONE 'UTC';
  v_spot      RECORD;
  v_claimed   BOOLEAN;
  -- Random offset ±0.04° ≈ ±4 km
  v_lat_off   DOUBLE PRECISION;
  v_lng_off   DOUBLE PRECISION;
BEGIN
  -- Try seller-sponsored spot first, then system
  SELECT s.*, u.name AS seller_name, u.avatar AS seller_avatar
  INTO v_spot
  FROM map_mystery_spots s
  LEFT JOIN users u ON u.id = s.seller_id
  WHERE s.spot_date = v_today
  ORDER BY s.is_seller_sponsored DESC, s.created_at ASC
  LIMIT 1;

  -- Create system spot if none exists
  IF v_spot IS NULL THEN
    v_lat_off := (random() * 0.08) - 0.04;
    v_lng_off := (random() * 0.08) - 0.04;
    INSERT INTO map_mystery_spots (spot_date, latitude, longitude, qarmet_reward)
    VALUES (v_today, p_lat + v_lat_off, p_lng + v_lng_off, 20)
    RETURNING * INTO v_spot;
  END IF;

  -- Check if current user already claimed it
  SELECT EXISTS (
    SELECT 1 FROM map_mystery_spot_claims
    WHERE spot_id = v_spot.id AND user_id = v_user_id
  ) INTO v_claimed;

  RETURN jsonb_build_object(
    'id',                   v_spot.id,
    'latitude',             v_spot.latitude,
    'longitude',            v_spot.longitude,
    'is_seller_sponsored',  v_spot.is_seller_sponsored,
    'seller_name',          v_spot.seller_name,
    'seller_offer',         v_spot.seller_offer,
    'seller_id',            v_spot.seller_id,
    'product_id',           v_spot.product_id,
    'qarmet_reward',        v_spot.qarmet_reward,
    'already_claimed',      COALESCE(v_claimed, false)
  );
END;
$$;

-- -----------------------------------------------------------------------
-- RPC: reveal_mystery_spot
-- Claims the spot, awards Qarmet. Idempotent (returns already_claimed=true).
-- -----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION reveal_mystery_spot(p_spot_id UUID)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID    := auth.uid();
  v_reward  INTEGER;
  v_balance INTEGER;
  v_spot    RECORD;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthenticated');
  END IF;

  SELECT * INTO v_spot FROM map_mystery_spots WHERE id = p_spot_id;
  IF v_spot IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;

  -- Idempotent claim
  BEGIN
    INSERT INTO map_mystery_spot_claims (spot_id, user_id)
    VALUES (p_spot_id, v_user_id);
  EXCEPTION WHEN unique_violation THEN
    SELECT qarmet_balance INTO v_balance FROM users WHERE id = v_user_id;
    RETURN jsonb_build_object(
      'success', true, 'already_claimed', true,
      'qarmet_awarded', 0, 'new_balance', v_balance
    );
  END;

  -- Award Qarmet
  UPDATE users
  SET qarmet_balance = qarmet_balance + v_spot.qarmet_reward
  WHERE id = v_user_id
  RETURNING qarmet_balance INTO v_balance;

  RETURN jsonb_build_object(
    'success',         true,
    'already_claimed', false,
    'qarmet_awarded',  v_spot.qarmet_reward,
    'new_balance',     v_balance,
    'is_seller_sponsored', v_spot.is_seller_sponsored,
    'seller_offer',    v_spot.seller_offer,
    'product_id',      v_spot.product_id
  );
END;
$$;

-- -----------------------------------------------------------------------
-- RPC: purchase_mystery_spot_slot
-- Seller sponsors tomorrow's mystery spot. Min 200 Qarmet.
-- Only one sponsored spot per day allowed.
-- -----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION purchase_mystery_spot_slot(
  p_offer_text TEXT,
  p_product_id UUID,
  p_bid_amount INTEGER  -- min 200 Qarmet
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id   UUID    := auth.uid();
  v_tomorrow  DATE    := (CURRENT_DATE AT TIME ZONE 'UTC') + 1;
  v_balance   INTEGER;
  v_spot_id   UUID;
  v_prod_lat  DOUBLE PRECISION;
  v_prod_lng  DOUBLE PRECISION;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthenticated');
  END IF;

  IF p_bid_amount < 200 THEN
    RETURN jsonb_build_object('success', false, 'error', 'bid_too_low', 'min', 200);
  END IF;

  -- Only one sponsored slot per day
  IF EXISTS (SELECT 1 FROM map_mystery_spots
             WHERE spot_date = v_tomorrow AND is_seller_sponsored = TRUE) THEN
    RETURN jsonb_build_object('success', false, 'error', 'slot_taken');
  END IF;

  SELECT qarmet_balance INTO v_balance FROM users WHERE id = v_user_id;
  IF v_balance < p_bid_amount THEN
    RETURN jsonb_build_object(
      'success', false, 'error', 'insufficient_balance',
      'required', p_bid_amount, 'balance', v_balance
    );
  END IF;

  -- Get product location (spot appears near the product)
  SELECT latitude, longitude INTO v_prod_lat, v_prod_lng
  FROM products WHERE id = p_product_id AND seller_id = v_user_id;

  IF v_prod_lat IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'product_not_found');
  END IF;

  UPDATE users SET qarmet_balance = qarmet_balance - p_bid_amount WHERE id = v_user_id;

  INSERT INTO map_mystery_spots (
    spot_date, latitude, longitude,
    is_seller_sponsored, seller_id, seller_offer,
    product_id, qarmet_reward
  ) VALUES (
    v_tomorrow,
    -- Spot appears slightly offset from the product (~200m)
    v_prod_lat + (random() * 0.004 - 0.002),
    v_prod_lng + (random() * 0.004 - 0.002),
    TRUE, v_user_id, p_offer_text,
    p_product_id,
    -- Users get 15% of what seller paid as their reward
    GREATEST(10, (p_bid_amount * 15) / 100)
  )
  RETURNING id INTO v_spot_id;

  RETURN jsonb_build_object(
    'success',     true,
    'spot_id',     v_spot_id,
    'new_balance', v_balance - p_bid_amount,
    'spot_date',   v_tomorrow::TEXT
  );
END;
$$;

COMMENT ON TABLE map_mystery_spots IS
  'MAP-6: Daily mystery "?" marker. System=20Q reward. Seller-sponsored: seller pays Qarmet, users get 15% as reward.';
