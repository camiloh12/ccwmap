-- 010_get_pins_in_view_geography_safe.sql
-- Phase 7 hotfix. Makes get_pins_in_view's cluster branch work regardless of
-- whether pins.location is `geometry` or `geography`.
--
-- Root cause: prod (the original project, built from the pre-consolidation
-- 001-003 baseline) has `pins.location` typed as GEOGRAPHY — see CLAUDE.md
-- "Remote Database". The consolidated 000_baseline.sql that built staging
-- types it as GEOMETRY. Migration 008's cluster branch calls
-- `ST_SnapToGrid(p.location, grid_size)`, and ST_SnapToGrid has NO geography
-- overload, so on prod every zoom-out (zoom < 12) request raised
-- `42883: function st_snaptogrid(geography, double precision) does not exist`
-- and the client rendered no clusters. The pin branch (zoom >= 12) never calls
-- ST_SnapToGrid, which is why zoom-in kept working. Staging (geometry) never
-- hit it.
--
-- Fix: cast `p.location::geometry` inside ST_SnapToGrid only. That cast is a
-- no-op when location is geometry and resolves to planar geometry when it is
-- geography, so the grid snap works in degrees (SRID 4326) regardless of the
-- column type. (011_location_geography_parity converges every environment on
-- geography to match prod; this function stays correct either way.) We do NOT
-- touch `ST_Intersects(p.location, bbox)` — it already resolves on both
-- environments (geometry->geography is an implicit cast) and keeps using the
-- GIST index; casting the indexed column there would defeat the index.
--
-- Deployed as CREATE OR REPLACE with the identical signature so existing
-- GRANTs are preserved and NOTHING else in migration 008 (the user_modified
-- backfill UPDATE, triggers, RLS) is re-run — re-running full 008 post-import
-- would flip user_modified=true on every imported system pin and block future
-- importer reconciliation.

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
  -- bbox stays geometry. ST_Intersects(p.location, bbox) resolves on both a
  -- geometry and a geography location column (geometry->geography implicit
  -- cast on prod) and keeps using the GIST index either way.
  bbox geometry := ST_MakeEnvelope(sw_lng, sw_lat, ne_lng, ne_lat, 4326);
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

    -- Every cell in the viewport returns as a cluster row, regardless of
    -- count. The client (map_screen) renders cnt<5 clusters as small
    -- pin-sized dots without count labels, and cnt>=5 clusters as scaled
    -- bubbles with count labels — see docs/dev/CLUSTER_RENDERING.md
    -- (Option B). This keeps the response shape homogeneous (no mixed
    -- pin+cluster rows) and lets the client cleanly hide its
    -- cached-pins-layer whenever clusters are present, eliminating the
    -- double-render of pins underneath clusters on zoom-out.
    --
    -- Centroid: AVG of constituent pin coordinates, NOT the grid anchor.
    -- Grid anchors land at arbitrary spots (often in oceans for coastal
    -- cells); the mean position tracks where the pins actually are.
    --
    -- IMPORTANT: every column projected out of `bucketed` must use an
    -- alias that does NOT appear in the RETURNS TABLE column list above.
    -- RETURNS TABLE implicitly declares OUT variables (latitude, longitude,
    -- status, restriction_tag, …) that shadow any unqualified reference to
    -- a same-named CTE column, raising 42702 at runtime. That's why every
    -- column gets a `bucket_*` alias here.
    --
    -- p.location::geometry: no-op when location is geometry, and the required
    -- explicit cast when it is geography, so ST_SnapToGrid — which has no
    -- geography overload — resolves. This is the whole point of migration 010.
    RETURN QUERY
    WITH bucketed AS (
      SELECT
        ST_SnapToGrid(p.location::geometry, grid_size) AS cell,
        p.latitude        AS bucket_lat,
        p.longitude       AS bucket_lng,
        p.status          AS bucket_status,
        p.restriction_tag AS bucket_tag
      FROM pins p
      WHERE ST_Intersects(p.location, bbox)
        AND (auth.uid() IS NULL OR p.created_by IS DISTINCT FROM auth.uid())
    ),
    aggregated AS (
      SELECT
        cell,
        count(*)                                       AS cnt,
        avg(bucket_lat)                                AS centroid_lat,
        avg(bucket_lng)                                AS centroid_lng,
        mode() WITHIN GROUP (ORDER BY bucket_status)   AS dom_status,
        mode() WITHIN GROUP (ORDER BY bucket_tag)      AS dom_tag
      FROM bucketed
      GROUP BY cell
    )
    SELECT
      'cluster'::TEXT,
      NULL::UUID,
      centroid_lat,
      centroid_lng,
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
