-- MAP-4: Zone Takeover
-- Business buys a geo-zone on the map. All users inside see a brand banner.

CREATE TABLE IF NOT EXISTS map_zones (
  id             UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id       UUID          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name           TEXT          NOT NULL,
  description    TEXT,
  offer_text     TEXT,           -- e.g. "Скидка 10% при показе этого экрана"
  brand_color    TEXT          NOT NULL DEFAULT '#2563EB',
  latitude       DOUBLE PRECISION NOT NULL,
  longitude      DOUBLE PRECISION NOT NULL,
  radius_meters  INTEGER       NOT NULL DEFAULT 500 CHECK (radius_meters IN (500, 1000)),
  active_until   TIMESTAMPTZ   NOT NULL,
  created_at     TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- Fast lookup of currently active zones
CREATE INDEX IF NOT EXISTS idx_map_zones_active
  ON map_zones (active_until DESC)
  WHERE active_until > NOW();

CREATE INDEX IF NOT EXISTS idx_map_zones_owner
  ON map_zones (owner_id);

-- -----------------------------------------------------------------------
-- RPC: get_active_zones
-- Returns all currently active zones with owner profile.
-- -----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_active_zones()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rows jsonb;
BEGIN
  SELECT jsonb_agg(
    jsonb_build_object(
      'id',            z.id,
      'owner_id',      z.owner_id,
      'name',          z.name,
      'description',   z.description,
      'offer_text',    z.offer_text,
      'brand_color',   z.brand_color,
      'latitude',      z.latitude,
      'longitude',     z.longitude,
      'radius_meters', z.radius_meters,
      'active_until',  z.active_until,
      'owner_avatar',  u.avatar
    )
  )
  INTO v_rows
  FROM map_zones z
  JOIN users u ON u.id = z.owner_id
  WHERE z.active_until > NOW();

  RETURN COALESCE(v_rows, '[]'::jsonb);
END;
$$;

-- -----------------------------------------------------------------------
-- Pricing:
--   500m / 7d  = 2000 Qarmet
--   500m / 30d = 6000 Qarmet
--   1km  / 7d  = 4000 Qarmet
--   1km  / 30d = 12000 Qarmet
-- -----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION purchase_map_zone(
  p_name          TEXT,
  p_description   TEXT,
  p_offer_text    TEXT,
  p_brand_color   TEXT,
  p_latitude      DOUBLE PRECISION,
  p_longitude     DOUBLE PRECISION,
  p_radius_meters INTEGER,   -- 500 or 1000
  p_duration_days INTEGER    -- 7 or 30
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id  UUID    := auth.uid();
  v_cost     INTEGER;
  v_balance  INTEGER;
  v_zone_id  UUID;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthenticated');
  END IF;

  IF p_radius_meters NOT IN (500, 1000) THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_radius');
  END IF;

  IF p_duration_days NOT IN (7, 30) THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_duration');
  END IF;

  -- Cost matrix
  v_cost := CASE
    WHEN p_radius_meters = 500  AND p_duration_days = 7  THEN 2000
    WHEN p_radius_meters = 500  AND p_duration_days = 30 THEN 6000
    WHEN p_radius_meters = 1000 AND p_duration_days = 7  THEN 4000
    WHEN p_radius_meters = 1000 AND p_duration_days = 30 THEN 12000
    ELSE 2000
  END;

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

  INSERT INTO map_zones (
    owner_id, name, description, offer_text,
    brand_color, latitude, longitude, radius_meters, active_until
  ) VALUES (
    v_user_id, p_name, p_description, p_offer_text,
    p_brand_color, p_latitude, p_longitude, p_radius_meters,
    NOW() + (p_duration_days || ' days')::INTERVAL
  )
  RETURNING id INTO v_zone_id;

  RETURN jsonb_build_object(
    'success',     true,
    'zone_id',     v_zone_id,
    'cost',        v_cost,
    'new_balance', v_balance - v_cost
  );
END;
$$;

COMMENT ON TABLE map_zones IS
  'MAP-4: Paid geo-zones on the map. Business buys visibility circle with branding and offer.';
