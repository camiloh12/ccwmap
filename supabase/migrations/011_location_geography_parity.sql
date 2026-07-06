-- 011_location_geography_parity.sql
-- Aligns pins.location to GEOGRAPHY so staging (and any environment built from
-- the consolidated 000_baseline.sql) matches production.
--
-- Background: prod (the original project, gqbxloaqamokbolcvesg) was built from
-- the hand-applied 001-003 baseline and has always typed pins.location as
-- GEOGRAPHY — see CLAUDE.md "Remote Database". The consolidated
-- 000_baseline.sql that built staging typed it as GEOMETRY. That drift meant
-- staging never exercised prod's spatial code path; it surfaced as
-- get_pins_in_view's cluster branch throwing 42883 on prod only
-- (ST_SnapToGrid has no geography overload) while working on staging. This
-- migration removes the drift so staging faithfully reproduces prod before we
-- promote anything.
--
-- Guarded + idempotent: converts ONLY when the column is currently geometry.
-- On prod (already geography) it is a no-op, so it is safe to apply anywhere.
-- location is GENERATED ALWAYS from longitude/latitude, so dropping and
-- re-adding it recomputes every row from the untouched lat/lng columns — no
-- pin data is lost. Only idx_pins_location depends on the column (verified via
-- pg_depend); we drop and recreate it.
--
-- The generation expression is written WITHOUT an explicit ::geography cast to
-- exactly mirror prod's stored definition (information_schema reports it as
-- `st_setsrid(st_makepoint(longitude, latitude), 4326)`); Postgres applies the
-- geometry->geography assignment cast when storing into the geography column.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'pins'
      AND column_name = 'location'
      AND udt_name = 'geometry'
  ) THEN
    DROP INDEX IF EXISTS idx_pins_location;

    ALTER TABLE public.pins DROP COLUMN location;

    ALTER TABLE public.pins
      ADD COLUMN location geography GENERATED ALWAYS AS
        (ST_SetSRID(ST_MakePoint(longitude, latitude), 4326))
        STORED;

    CREATE INDEX IF NOT EXISTS idx_pins_location
      ON public.pins USING GIST (location);

    RAISE NOTICE 'pins.location converted geometry -> geography';
  ELSE
    RAISE NOTICE 'pins.location already geography (or absent) — no change';
  END IF;
END $$;
