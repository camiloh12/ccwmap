-- 008_provenance_and_view_rpc.sql
-- Phase 0 of the pre-populate-pins project. Adds provenance columns to
-- pins, the audit/operations tables that the Phase 2 importer and the
-- Phase 1 sync rewrite will use, the triggers that keep them consistent,
-- the bbox+cluster RPC that Phase 1 calls, and the column-level UPDATE
-- grants that prevent authenticated users from forging provenance fields.
--
-- Spec: docs/superpowers/specs/2026-05-10-pre-populate-pins-design.md §3,§5,§6,§7
-- Plan: docs/superpowers/plans/2026-05-16-pre-populate-pins-phase-0.md

-- =============================================================================
-- §1  Provenance columns on pins
-- =============================================================================

ALTER TABLE pins
  ADD COLUMN IF NOT EXISTS source TEXT NOT NULL DEFAULT 'user',
  ADD COLUMN IF NOT EXISTS source_external_id TEXT,
  ADD COLUMN IF NOT EXISTS source_dataset_version TEXT,
  ADD COLUMN IF NOT EXISTS imported_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS user_modified BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS confidence TEXT
    CHECK (confidence IS NULL OR confidence IN ('high','medium','low')),
  ADD COLUMN IF NOT EXISTS legal_citation TEXT,
  ADD COLUMN IF NOT EXISTS legal_citation_verified_date DATE,
  ADD COLUMN IF NOT EXISTS source_orphaned_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS cached_at TIMESTAMPTZ;

-- Backfill: every pin that existed before this migration was user-created
-- and has been touched by a user. user_modified=true ensures subsequent
-- importer runs cannot overwrite these rows even if a future importer ever
-- targets source='user' (it should not — but defense in depth).
UPDATE pins SET user_modified = true WHERE user_modified = false;

-- Compound index for the importer's primary lookup key.
CREATE INDEX IF NOT EXISTS pins_source_external_id_idx
  ON pins (source, source_external_id)
  WHERE source_external_id IS NOT NULL;

-- =============================================================================
-- §2  Spatial index used by get_pins_in_view (likely already present;
--     CREATE IF NOT EXISTS makes the migration safe on either project state)
-- =============================================================================

CREATE INDEX IF NOT EXISTS pins_location_gist
  ON pins USING GIST (location);

-- =============================================================================
-- §3  pin_deletions  (server-side tombstones, mirrored to local DB by
--                     Phase 1's MyPinsSync)
-- =============================================================================

CREATE TABLE IF NOT EXISTS pin_deletions (
  pin_id              UUID        PRIMARY KEY,
  deleted_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_by          UUID,
  original_created_by UUID
);

CREATE INDEX IF NOT EXISTS pin_deletions_deleted_at_idx
  ON pin_deletions (deleted_at);
CREATE INDEX IF NOT EXISTS pin_deletions_original_created_by_idx
  ON pin_deletions (original_created_by);

ALTER TABLE pin_deletions ENABLE ROW LEVEL SECURITY;

-- Authenticated users can read tombstones for pins they created. Used by
-- the (Phase 1) MyPinsSync delta query: "what of mine has been deleted
-- since my last sync?".
DROP POLICY IF EXISTS "pin_deletions_owner_read" ON pin_deletions;
CREATE POLICY "pin_deletions_owner_read" ON pin_deletions
  FOR SELECT USING (auth.uid() = original_created_by);

-- No INSERT/UPDATE/DELETE policies — only the record_pin_deletion trigger
-- (running with SECURITY DEFINER) writes here.

-- =============================================================================
-- §4  import_runs  (audit log of every importer apply)
-- =============================================================================

CREATE TABLE IF NOT EXISTS import_runs (
  run_id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  started_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at         TIMESTAMPTZ,
  mode                 TEXT        CHECK (mode IN ('dry-run','apply')),
  source_filter        TEXT,
  candidates_processed INT,
  inserts              INT,
  updates              INT,
  skips                INT,
  orphans_marked       INT,
  errors_json          JSONB,
  report_artifact_url  TEXT
);

ALTER TABLE import_runs ENABLE ROW LEVEL SECURITY;
-- No policies — service role only.

-- =============================================================================
-- §5  recent_deletes  (rolling counter for the rate-limit trigger;
--                      pruned by the Phase 6 daily health-check)
-- =============================================================================

CREATE TABLE IF NOT EXISTS recent_deletes (
  user_id    UUID        NOT NULL,
  deleted_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS recent_deletes_user_id_deleted_at_idx
  ON recent_deletes (user_id, deleted_at);

ALTER TABLE recent_deletes ENABLE ROW LEVEL SECURITY;
-- No policies — written by enforce_delete_rate_limit (SECURITY DEFINER),
-- read by future health-check, never user-visible.

-- =============================================================================
-- §6  Triggers
-- =============================================================================

-- 6a. set_user_modified — fire on UPDATE from anyone except service_role.
--     Tracks that a user has touched the row so the importer skips it on
--     subsequent runs.
CREATE OR REPLACE FUNCTION set_user_modified() RETURNS TRIGGER AS $$
BEGIN
  IF current_user <> 'service_role' THEN
    NEW.user_modified := true;
    NEW.last_modified := now();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS set_user_modified_trigger ON pins;
CREATE TRIGGER set_user_modified_trigger
  BEFORE UPDATE ON pins
  FOR EACH ROW
  EXECUTE FUNCTION set_user_modified();

-- 6b. record_pin_deletion — write a tombstone for every DELETE.
--     SECURITY DEFINER so the row gets inserted even when the deleter
--     lacks INSERT on pin_deletions (which they always do — no policy).
CREATE OR REPLACE FUNCTION record_pin_deletion() RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO pin_deletions (pin_id, deleted_at, deleted_by, original_created_by)
  VALUES (OLD.id, now(), auth.uid(), OLD.created_by);
  RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS record_pin_deletion_trigger ON pins;
CREATE TRIGGER record_pin_deletion_trigger
  AFTER DELETE ON pins
  FOR EACH ROW
  EXECUTE FUNCTION record_pin_deletion();

-- 6c. enforce_delete_rate_limit — per-user 100-deletes-per-hour limit.
--     Permissive enough for legitimate cleanup; tight enough that
--     scripted attacks fail loudly. Skipped for service_role and for
--     unauthenticated (anon) actions.
CREATE OR REPLACE FUNCTION enforce_delete_rate_limit() RETURNS TRIGGER AS $$
DECLARE
  v_user UUID := auth.uid();
  v_count INT;
BEGIN
  IF v_user IS NULL OR current_user = 'service_role' THEN
    RETURN OLD;
  END IF;

  INSERT INTO recent_deletes (user_id, deleted_at) VALUES (v_user, now());

  SELECT count(*) INTO v_count
  FROM recent_deletes
  WHERE user_id = v_user
    AND deleted_at > now() - interval '1 hour';

  IF v_count > 100 THEN
    RAISE EXCEPTION USING
      MESSAGE = 'Delete rate limit exceeded: more than 100 pin deletions per hour',
      ERRCODE = 'P0001';
  END IF;

  RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS enforce_delete_rate_limit_trigger ON pins;
CREATE TRIGGER enforce_delete_rate_limit_trigger
  BEFORE DELETE ON pins
  FOR EACH ROW
  EXECUTE FUNCTION enforce_delete_rate_limit();

-- =============================================================================
-- §7  get_pins_in_view RPC
--     Returns pins inside the bbox, excluding pins created by the caller
--     (those come down via MyPinsSync). At low zoom we cluster on a grid
--     so a national view never returns 50k rows.
-- =============================================================================

DROP FUNCTION IF EXISTS get_pins_in_view(
  double precision, double precision, double precision, double precision, integer
);

CREATE OR REPLACE FUNCTION get_pins_in_view(
  sw_lat double precision,
  sw_lng double precision,
  ne_lat double precision,
  ne_lng double precision,
  zoom   integer
) RETURNS TABLE (
  kind                          TEXT,
  pin_id                        UUID,
  latitude                      double precision,
  longitude                     double precision,
  name                          TEXT,
  status                        INTEGER,
  restriction_tag               restriction_tag_type,
  has_security_screening        BOOLEAN,
  has_posted_signage            BOOLEAN,
  created_by                    UUID,
  created_at                    TIMESTAMPTZ,
  last_modified                 TIMESTAMPTZ,
  source                        TEXT,
  source_external_id            TEXT,
  confidence                    TEXT,
  legal_citation                TEXT,
  legal_citation_verified_date  DATE,
  cluster_count                 INTEGER,
  dominant_status               INTEGER,
  dominant_restriction_tag      restriction_tag_type
)
LANGUAGE plpgsql
SECURITY INVOKER  -- respect RLS on pins; caller's auth.uid() reads through
AS $$
DECLARE
  bbox geography := ST_MakeEnvelope(sw_lng, sw_lat, ne_lng, ne_lat, 4326)::geography;
  candidate_count INT;
  grid_size double precision;
BEGIN
  -- Density check: even at zoom>=12, if the viewport holds >2000 candidate
  -- pins we cluster instead of returning the full set (pathological case
  -- like downtown LA at street zoom).
  SELECT count(*) INTO candidate_count
  FROM pins p
  WHERE ST_Intersects(p.location, bbox)
    AND (auth.uid() IS NULL OR p.created_by IS DISTINCT FROM auth.uid());

  IF zoom >= 12 AND candidate_count <= 2000 THEN
    RETURN QUERY
    SELECT
      'pin'::TEXT,
      p.id,
      p.latitude,
      p.longitude,
      p.name,
      p.status,
      p.restriction_tag,
      p.has_security_screening,
      p.has_posted_signage,
      p.created_by,
      p.created_at,
      p.last_modified,
      p.source,
      p.source_external_id,
      p.confidence,
      p.legal_citation,
      p.legal_citation_verified_date,
      NULL::INTEGER,
      NULL::INTEGER,
      NULL::restriction_tag_type
    FROM pins p
    WHERE ST_Intersects(p.location, bbox)
      AND (auth.uid() IS NULL OR p.created_by IS DISTINCT FROM auth.uid())
    LIMIT 2000;
  ELSE
    -- Cluster on a zoom-dependent grid (in degrees, since we snap to
    -- a geometry grid).
    grid_size := CASE
      WHEN zoom < 4  THEN 4.0
      WHEN zoom < 6  THEN 2.0
      WHEN zoom < 8  THEN 1.0
      WHEN zoom < 10 THEN 0.5
      WHEN zoom < 12 THEN 0.1
      ELSE                 0.05  -- density-fallback at zoom>=12 over-dense bbox
    END;

    RETURN QUERY
    WITH bucketed AS (
      SELECT
        ST_SnapToGrid(p.location::geometry, grid_size) AS cell,
        p.status,
        p.restriction_tag
      FROM pins p
      WHERE ST_Intersects(p.location, bbox)
        AND (auth.uid() IS NULL OR p.created_by IS DISTINCT FROM auth.uid())
    ),
    aggregated AS (
      SELECT
        cell,
        count(*) AS cnt,
        mode() WITHIN GROUP (ORDER BY status)          AS dom_status,
        mode() WITHIN GROUP (ORDER BY restriction_tag) AS dom_tag
      FROM bucketed
      GROUP BY cell
    )
    SELECT
      'cluster'::TEXT,
      NULL::UUID,
      ST_Y(cell),
      ST_X(cell),
      NULL::TEXT,
      NULL::INTEGER,
      NULL::restriction_tag_type,
      NULL::BOOLEAN,
      NULL::BOOLEAN,
      NULL::UUID,
      NULL::TIMESTAMPTZ,
      NULL::TIMESTAMPTZ,
      NULL::TEXT,
      NULL::TEXT,
      NULL::TEXT,
      NULL::TEXT,
      NULL::DATE,
      cnt::INTEGER,
      dom_status,
      dom_tag
    FROM aggregated;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION get_pins_in_view(
  double precision, double precision, double precision, double precision, integer
) TO anon, authenticated;

-- =============================================================================
-- §8  Column-level UPDATE grants — block authenticated users from forging
--     provenance fields. Service role retains full UPDATE access.
-- =============================================================================

REVOKE UPDATE ON pins FROM authenticated;

GRANT UPDATE
  (name, latitude, longitude, status, restriction_tag,
   has_security_screening, has_posted_signage, notes, photo_uri, votes)
  ON pins TO authenticated;

-- =============================================================================
-- §9  System-user deny-write RLS policy
--     Even if the system user's password leaks, an authenticated session
--     attempting to write rows attributed to the system user is rejected.
--     The importer uses service_role, which bypasses RLS entirely.
-- =============================================================================

DROP POLICY IF EXISTS "deny_system_user_writes" ON pins;
CREATE POLICY "deny_system_user_writes" ON pins
  AS RESTRICTIVE
  FOR ALL
  TO authenticated
  USING (created_by IS DISTINCT FROM '81775f8b-1a6a-47d6-b793-e9ab7e38634e'::uuid)
  WITH CHECK (created_by IS DISTINCT FROM '81775f8b-1a6a-47d6-b793-e9ab7e38634e'::uuid);

-- =============================================================================
-- End of migration 008.
-- =============================================================================
