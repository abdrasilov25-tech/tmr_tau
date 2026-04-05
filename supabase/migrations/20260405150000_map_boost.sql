-- MAP-2.1: Map Boost for sellers
-- Adds boost columns to products and purchase_map_boost RPC.

-- 1. Add columns to products table
ALTER TABLE products
  ADD COLUMN IF NOT EXISTS map_boost_level   INTEGER      NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS map_boost_expires_at TIMESTAMPTZ;

-- Index for filtering active boosts efficiently
CREATE INDEX IF NOT EXISTS idx_products_map_boost
  ON products (map_boost_level, map_boost_expires_at)
  WHERE map_boost_level > 0;

-- 2. RPC: purchase_map_boost
-- Deducts Qarmet from buyer's balance and activates boost on the product.
-- Returns jsonb with success flag, cost, new_balance.
CREATE OR REPLACE FUNCTION purchase_map_boost(
  p_product_id   UUID,
  p_boost_level  INTEGER,   -- 1 = Boost (50 Qarmet/day), 2 = Top Zone (150 Qarmet/day)
  p_duration_hours INTEGER  -- must be multiple of 24: 24, 72, 168
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
  -- Validate level
  IF p_boost_level NOT IN (1, 2) THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_level');
  END IF;

  -- Validate duration
  IF p_duration_hours NOT IN (24, 72, 168) THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_duration');
  END IF;

  -- Verify product ownership
  SELECT seller_id INTO v_product_seller_id
  FROM products
  WHERE id = p_product_id;

  IF v_product_seller_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'product_not_found');
  END IF;

  IF v_product_seller_id <> v_user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_owner');
  END IF;

  -- Calculate cost (50 Qarmet/day for boost, 150 Qarmet/day for top zone)
  v_cost := CASE p_boost_level
    WHEN 1 THEN 50  * (p_duration_hours / 24)
    WHEN 2 THEN 150 * (p_duration_hours / 24)
  END;

  -- Check Qarmet balance
  SELECT qarmet_balance INTO v_current_balance
  FROM users
  WHERE id = v_user_id;

  IF v_current_balance IS NULL OR v_current_balance < v_cost THEN
    RETURN jsonb_build_object(
      'success',  false,
      'error',    'insufficient_balance',
      'required', v_cost,
      'balance',  COALESCE(v_current_balance, 0)
    );
  END IF;

  -- Deduct Qarmet
  UPDATE users
  SET qarmet_balance = qarmet_balance - v_cost
  WHERE id = v_user_id;

  -- Activate boost (extend if already active)
  UPDATE products
  SET
    map_boost_level     = p_boost_level,
    map_boost_expires_at = GREATEST(
      COALESCE(map_boost_expires_at, NOW()),
      NOW()
    ) + (p_duration_hours || ' hours')::INTERVAL
  WHERE id = p_product_id;

  RETURN jsonb_build_object(
    'success',     true,
    'cost',        v_cost,
    'new_balance', v_current_balance - v_cost
  );
END;
$$;

COMMENT ON FUNCTION purchase_map_boost IS
  'MAP-2.1: Deducts Qarmet from seller balance and activates map boost on product. Level 1=Boost (50Q/day), Level 2=TopZone (150Q/day).';
