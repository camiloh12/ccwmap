-- staging_density_seed.sql
-- Synthetic test data for Phase 1 end-to-end verification (Task 18).
--
-- Inserts ~2,025 pins owned by the system user across six dense US metros
-- plus 15 mid-size-metro mini-clusters for national coverage. Exercises:
--   - Server-side clustering (get_pins_in_view RPC, multiple zoom buckets)
--   - ViewportPinsManager bbox-on-demand fetch + LRU cache
--   - Pin-vs-cluster layer visibility toggling on the map
--   - Pathological-cache fallback (>40k limit is NOT hit; intentional —
--     this seed is realistic-pilot scale, not stress-test scale)
--
-- Run location:
--   Supabase Dashboard → SQL Editor on the STAGING project
--   (ccwmap-staging, ref miihmfhnsfmwgrvgayns).
--   SQL Editor runs as postgres superuser, bypassing RLS — including the
--   deny_system_user_insert RESTRICTIVE policy from migration 008. Do NOT
--   attempt to run this via PostgREST with an anon/auth key; that policy
--   will reject every row.
--
-- Idempotency:
--   Re-runnable. The opening DELETE removes any prior rows with
--   source = 'staging-seed-2026-05'. setseed(0.42) makes the random
--   placement deterministic, so reruns produce the same coordinates.
--
-- Cleanup:
--   To wipe the seed entirely, run the DELETE block at the bottom.
--
-- Spec/plan: Phase 1 of docs/superpowers/specs/2026-05-10-pre-populate-pins-design.md

BEGIN;

-- Deterministic placement across reruns.
SELECT setseed(0.42);

-- Idempotency: clear any prior seed rows. Filter is precise — only this
-- seed's marker source value is removed; real user pins (source='user')
-- and any other seed/import sources are left alone.
DELETE FROM pins WHERE source = 'staging-seed-2026-05';

-- =============================================================================
-- Generation
-- =============================================================================
--
-- Six metros chosen for clustering visibility:
--   - NYC, SF, LA, Chicago: largest US metros, expected dense markets
--   - Austin: mid-size, Texas — important per project competitive landscape
--   - DC: federal-density region, mirrors what Phase 4 wave 1 will surface
--
-- Plus 15 mid-size metros (Denver, Seattle, Phoenix, Minneapolis, Atlanta,
-- Boston, Miami, New Orleans, Portland, Salt Lake, Detroit, Nashville,
-- Kansas City, OKC, Las Vegas) with ~15 pins each, so country-zoom shows
-- clusters across the country instead of just six hotspots. Anchored
-- placement (vs. random continental-bbox scatter) keeps every pin on or
-- adjacent to land — no Atlantic / Gulf / Pacific phantom pins.
--
-- Distribution per pin (deterministic via setseed):
--   status:           60% NO_GUN, 20% ALLOWED, 20% UNCERTAIN
--   restriction_tag:  uniform over the 10 enum values, only when NO_GUN
--   security/signage: ~33% / ~50% true
--
-- All rows attributed to the system user (81775f8b-…), source marker
-- 'staging-seed-2026-05', confidence 'high'. user_modified=false matches
-- importer-owned data and lets the deny_system_user_update policy serve
-- its real purpose in tests.

WITH cities (city_name, lat, lng, pin_count, radius_deg) AS (
  VALUES
    ('NYC',     40.7128::double precision,  -74.0060::double precision, 500, 0.35::double precision),
    ('SF',      37.7749,                    -122.4194,                  400, 0.35),
    ('LA',      34.0522,                    -118.2437,                  350, 0.40),
    ('Chicago', 41.8781,                     -87.6298,                  250, 0.30),
    ('Austin',  30.2672,                     -97.7431,                  150, 0.25),
    ('DC',      38.9072,                     -77.0369,                  150, 0.25)
),
city_pins AS (
  SELECT
    c.city_name,
    g AS idx,
    c.lat + (random() - 0.5) * c.radius_deg * 2 AS pin_lat,
    c.lng + (random() - 0.5) * c.radius_deg * 2 AS pin_lng,
    floor(random() * 5)::int  AS status_seed,
    floor(random() * 10)::int AS tag_seed
  FROM cities c,
       LATERAL generate_series(1, c.pin_count) g
),
scatter_cities (city_name, lat, lng, pin_count, radius_deg) AS (VALUES
  -- Anchored mini-clusters around mid-size US metros. ~15 pins each, tight
  -- radius — guarantees pins land on or very near land (no Atlantic /
  -- Gulf / Pacific scatter) and produces visible density across the
  -- country at low zoom without polluting the map with random points.
  ('Denver',      39.7392::double precision, -104.9903::double precision, 15, 0.20::double precision),
  ('Seattle',     47.6062,                   -122.3321,                   15, 0.20),
  ('Phoenix',     33.4484,                   -112.0740,                   15, 0.20),
  ('Minneapolis', 44.9778,                    -93.2650,                   15, 0.20),
  ('Atlanta',     33.7490,                    -84.3880,                   15, 0.20),
  ('Boston',      42.3601,                    -71.0589,                   15, 0.18),
  ('Miami',       25.7617,                    -80.1918,                   15, 0.18),
  ('New Orleans', 29.9511,                    -90.0715,                   15, 0.18),
  ('Portland',    45.5152,                   -122.6784,                   15, 0.18),
  ('Salt Lake',   40.7608,                   -111.8910,                   15, 0.18),
  ('Detroit',     42.3314,                    -83.0458,                   15, 0.20),
  ('Nashville',   36.1627,                    -86.7816,                   15, 0.20),
  ('Kansas City', 39.0997,                    -94.5786,                   15, 0.20),
  ('OKC',         35.4676,                    -97.5164,                   15, 0.20),
  ('Las Vegas',   36.1699,                   -115.1398,                   15, 0.18)
),
scatter_pins AS (
  SELECT
    c.city_name,
    g AS idx,
    c.lat + (random() - 0.5) * c.radius_deg * 2 AS pin_lat,
    c.lng + (random() - 0.5) * c.radius_deg * 2 AS pin_lng,
    floor(random() * 5)::int  AS status_seed,
    floor(random() * 10)::int AS tag_seed
  FROM scatter_cities c,
       LATERAL generate_series(1, c.pin_count) g
),
all_pins AS (
  SELECT * FROM city_pins
  UNION ALL
  SELECT * FROM scatter_pins
)
INSERT INTO pins (
  name,
  latitude,
  longitude,
  status,
  restriction_tag,
  has_security_screening,
  has_posted_signage,
  created_by,
  source,
  source_external_id,
  source_dataset_version,
  imported_at,
  user_modified,
  confidence
)
SELECT
  -- 60-char CHECK from migration 007 — keep names short.
  city_name || ' Test #' || idx,
  pin_lat,
  pin_lng,
  CASE status_seed
    WHEN 0 THEN 2   -- NO_GUN
    WHEN 1 THEN 2
    WHEN 2 THEN 2
    WHEN 3 THEN 0   -- ALLOWED
    ELSE        1   -- UNCERTAIN
  END,
  CASE
    WHEN status_seed IN (0, 1, 2) THEN
      (ARRAY[
        'FEDERAL_PROPERTY',
        'AIRPORT_SECURE',
        'STATE_LOCAL_GOVT',
        'SCHOOL_K12',
        'COLLEGE_UNIVERSITY',
        'BAR_ALCOHOL',
        'HEALTHCARE',
        'PLACE_OF_WORSHIP',
        'SPORTS_ENTERTAINMENT',
        'PRIVATE_PROPERTY'
      ]::public.restriction_tag_type[])[tag_seed + 1]
    ELSE NULL
  END,
  (tag_seed % 3 = 0),                                                -- ~33% screening
  (tag_seed % 2 = 0),                                                -- ~50% signage
  '81775f8b-1a6a-47d6-b793-e9ab7e38634e'::uuid,                      -- kSystemUserId
  'staging-seed-2026-05',
  city_name || '-' || idx,
  'staging-seed-v1',
  now(),
  false,
  'high'
FROM all_pins;

COMMIT;

-- =============================================================================
-- Verification
-- =============================================================================
-- Run after COMMIT. Expected: 2025 rows total
-- (500+400+350+250+150+150 city pins + 15 × 15 scatter mini-clusters).

SELECT
  count(*)                                              AS total_seeded,
  count(*) FILTER (WHERE status = 0)                    AS allowed,
  count(*) FILTER (WHERE status = 1)                    AS uncertain,
  count(*) FILTER (WHERE status = 2)                    AS no_gun,
  count(*) FILTER (WHERE restriction_tag IS NOT NULL)   AS tagged,
  count(*) FILTER (WHERE has_security_screening)        AS with_screening,
  count(*) FILTER (WHERE has_posted_signage)            AS with_signage,
  min(latitude)  AS min_lat, max(latitude)  AS max_lat,
  min(longitude) AS min_lng, max(longitude) AS max_lng
FROM pins
WHERE source = 'staging-seed-2026-05';

-- Sanity: confirm the RPC clusters at country zoom (zoom=3 → 4° grid).
-- Expect a handful of cluster rows, each with cnt in the hundreds.
SELECT kind, cluster_count, dominant_status, dominant_restriction_tag,
       round(latitude::numeric, 2) AS lat, round(longitude::numeric, 2) AS lng
FROM get_pins_in_view(24.4, -125.0, 49.4, -66.9, 3)
ORDER BY cluster_count DESC NULLS LAST
LIMIT 20;

-- Sanity: confirm the RPC returns individuals at street zoom in NYC
-- (zoom=14, tight bbox). Expect kind='pin' rows.
SELECT kind, name, status, restriction_tag
FROM get_pins_in_view(40.70, -74.02, 40.73, -73.99, 14)
LIMIT 20;

-- =============================================================================
-- Cleanup (uncomment to wipe the seed)
-- =============================================================================
--
-- BEGIN;
-- DELETE FROM pins WHERE source = 'staging-seed-2026-05';
-- COMMIT;
