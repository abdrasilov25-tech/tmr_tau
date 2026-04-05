-- MAP-2.2: Featured Seller of the Day (daily auction)
-- Sellers bid Qarmet. Highest bidder = featured on map for the day.
-- When outbid: previous leader gets 80% refund (20% platform fee).

CREATE TABLE IF NOT EXISTS map_featured_bids (
  id           UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  bid_amount   INTEGER      NOT NULL CHECK (bid_amount >= 200),
  bid_date     DATE         NOT NULL DEFAULT (CURRENT_DATE AT TIME ZONE 'UTC'),
  created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- One bid per user per day (upsert on conflict)
CREATE UNIQUE INDEX IF NOT EXISTS idx_featured_bids_user_date
  ON map_featured_bids (user_id, bid_date);

-- Fast lookup of daily leader
CREATE INDEX IF NOT EXISTS idx_featured_bids_date_amount
  ON map_featured_bids (bid_date DESC, bid_amount DESC);

-- -----------------------------------------------------------------------
-- RPC: get_today_featured
-- Returns the current day's top bidder with seller profile info.
-- -----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_today_featured()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today DATE := CURRENT_DATE AT TIME ZONE 'UTC';
  v_row   RECORD;
BEGIN
  SELECT
    b.user_id,
    b.bid_amount,
    u.name     AS seller_name,
    u.avatar   AS seller_avatar
  INTO v_row
  FROM map_featured_bids b
  JOIN users u ON u.id = b.user_id
  WHERE b.bid_date = v_today
  ORDER BY b.bid_amount DESC
  LIMIT 1;

  IF v_row IS NULL THEN
    RETURN jsonb_build_object('found', false);
  END IF;

  RETURN jsonb_build_object(
    'found',        true,
    'user_id',      v_row.user_id,
    'bid_amount',   v_row.bid_amount,
    'seller_name',  v_row.seller_name,
    'seller_avatar', v_row.seller_avatar
  );
END;
$$;

-- -----------------------------------------------------------------------
-- RPC: place_featured_bid
-- Places or upgrades today's bid.
-- - Minimum: 200 Qarmet, or current_top + 50 (whichever is higher).
-- - If outbidding someone else: previous leader gets 80% refund.
-- - If upgrading own bid: pay only the difference.
-- Returns jsonb {success, error?, bid_amount?, new_balance?, top_bid?}
-- -----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION place_featured_bid(p_bid_amount INTEGER)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id       UUID    := auth.uid();
  v_today         DATE    := CURRENT_DATE AT TIME ZONE 'UTC';
  v_balance       INTEGER;
  v_top_bid       INTEGER := 0;
  v_top_user      UUID;
  v_my_prev_bid   INTEGER := 0;
  v_cost          INTEGER;
  v_min_required  INTEGER;
  v_refund        INTEGER;
BEGIN
  -- Auth check
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthenticated');
  END IF;

  -- Get current leader
  SELECT bid_amount, user_id
  INTO v_top_bid, v_top_user
  FROM map_featured_bids
  WHERE bid_date = v_today
  ORDER BY bid_amount DESC
  LIMIT 1;

  v_top_bid := COALESCE(v_top_bid, 0);

  -- Check user's own existing bid
  SELECT bid_amount INTO v_my_prev_bid
  FROM map_featured_bids
  WHERE user_id = v_user_id AND bid_date = v_today;

  v_my_prev_bid := COALESCE(v_my_prev_bid, 0);

  -- Minimum required bid
  v_min_required := GREATEST(200, v_top_bid + 50);

  -- If user is already the leader, they can increase their own bid freely
  IF v_top_user = v_user_id THEN
    v_min_required := v_my_prev_bid + 1;
  END IF;

  IF p_bid_amount < v_min_required THEN
    RETURN jsonb_build_object(
      'success',      false,
      'error',        'bid_too_low',
      'min_required', v_min_required,
      'top_bid',      v_top_bid
    );
  END IF;

  -- Cost = full bid - previous own bid (upgrade)
  v_cost := p_bid_amount - v_my_prev_bid;

  -- Check balance
  SELECT qarmet_balance INTO v_balance FROM users WHERE id = v_user_id;
  IF v_balance < v_cost THEN
    RETURN jsonb_build_object(
      'success',  false,
      'error',    'insufficient_balance',
      'required', v_cost,
      'balance',  v_balance
    );
  END IF;

  -- Deduct from bidder
  UPDATE users SET qarmet_balance = qarmet_balance - v_cost WHERE id = v_user_id;

  -- Refund previous leader (80%) if it's a different user being displaced
  IF v_top_user IS NOT NULL AND v_top_user <> v_user_id AND v_top_bid > 0 THEN
    v_refund := (v_top_bid * 80) / 100;
    UPDATE users SET qarmet_balance = qarmet_balance + v_refund WHERE id = v_top_user;
  END IF;

  -- Upsert bid
  INSERT INTO map_featured_bids (user_id, bid_amount, bid_date)
  VALUES (v_user_id, p_bid_amount, v_today)
  ON CONFLICT (user_id, bid_date)
  DO UPDATE SET bid_amount = EXCLUDED.bid_amount, updated_at = NOW();

  RETURN jsonb_build_object(
    'success',     true,
    'bid_amount',  p_bid_amount,
    'new_balance', v_balance - v_cost,
    'top_bid',     p_bid_amount
  );
END;
$$;

COMMENT ON TABLE map_featured_bids IS
  'MAP-2.2: Daily Qarmet auction. Highest bidder is featured on the map. 80% refund when outbid.';
