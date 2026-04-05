-- MAP-5: Marker Sticker Packs
-- Sellers buy emoji packs (500 Qarmet each) and assign a sticker to their products.

-- Sticker emoji per product (visible on map marker)
ALTER TABLE products
  ADD COLUMN IF NOT EXISTS map_marker_sticker TEXT;

-- Which packs each user has purchased
CREATE TABLE IF NOT EXISTS map_sticker_packs (
  user_id      UUID  NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  pack_id      TEXT  NOT NULL,  -- 'animals' | 'kazakhstan' | 'seasonal_newyear'
  purchased_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY  (user_id, pack_id)
);

-- -----------------------------------------------------------------------
-- RPC: get_my_sticker_packs
-- Returns the list of pack_ids the calling user has purchased.
-- -----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_my_sticker_packs()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_packs   jsonb;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;

  SELECT jsonb_agg(pack_id) INTO v_packs
  FROM map_sticker_packs
  WHERE user_id = v_user_id;

  RETURN COALESCE(v_packs, '[]'::jsonb);
END;
$$;

-- -----------------------------------------------------------------------
-- RPC: purchase_sticker_pack
-- Costs 500 Qarmet per pack. Idempotent (no error if already owned).
-- -----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION purchase_sticker_pack(p_pack_id TEXT)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID    := auth.uid();
  v_cost    INTEGER := 500;
  v_balance INTEGER;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthenticated');
  END IF;

  IF p_pack_id NOT IN ('animals', 'kazakhstan', 'seasonal_newyear') THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_pack');
  END IF;

  -- Already owned — free success
  IF EXISTS (SELECT 1 FROM map_sticker_packs WHERE user_id = v_user_id AND pack_id = p_pack_id) THEN
    SELECT qarmet_balance INTO v_balance FROM users WHERE id = v_user_id;
    RETURN jsonb_build_object('success', true, 'already_owned', true, 'new_balance', v_balance);
  END IF;

  SELECT qarmet_balance INTO v_balance FROM users WHERE id = v_user_id;
  IF v_balance < v_cost THEN
    RETURN jsonb_build_object(
      'success',  false,
      'error',    'insufficient_balance',
      'required', v_cost,
      'balance',  v_balance
    );
  END IF;

  UPDATE users SET qarmet_balance = qarmet_balance - v_cost WHERE id = v_user_id;
  INSERT INTO map_sticker_packs (user_id, pack_id) VALUES (v_user_id, p_pack_id);

  RETURN jsonb_build_object('success', true, 'already_owned', false, 'new_balance', v_balance - v_cost);
END;
$$;

-- -----------------------------------------------------------------------
-- RPC: set_product_marker_sticker
-- Assigns (or clears) a sticker emoji on a product owned by the caller.
-- -----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_product_marker_sticker(
  p_product_id UUID,
  p_sticker    TEXT  -- emoji string, or NULL to clear
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthenticated');
  END IF;

  UPDATE products
  SET map_marker_sticker = p_sticker
  WHERE id = p_product_id AND seller_id = v_user_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_owner');
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$$;

COMMENT ON TABLE map_sticker_packs IS
  'MAP-5: Purchased emoji sticker packs per user. 500 Qarmet each.';
