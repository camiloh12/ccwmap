-- 000_baseline.sql
-- Captures the prod schema state that pre-dated the git-tracked migration
-- history (originally applied via Supabase Studio before 004 was committed).
-- Reconstructed from prod via MCP inspection on 2026-05-16.
--
-- Numbered `000` so it sorts before `004_user_agreements.sql` etc. and is
-- applied first when a fresh environment (e.g. staging) bootstraps.
--
-- Every statement is idempotent — re-applying against an already-populated
-- prod is a no-op. The pin_name length CHECK constraint added later by
-- 007_pin_name_length.sql is deliberately NOT included here; let 007 add
-- it as designed.

-- =============================================================================
-- Extensions
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;

-- =============================================================================
-- Enum: restriction_tag_type
-- =============================================================================

DO $$
BEGIN
  CREATE TYPE public.restriction_tag_type AS ENUM (
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
  );
EXCEPTION WHEN duplicate_object THEN
  -- enum already exists; leave it alone
  NULL;
END $$;

-- =============================================================================
-- Function: update_last_modified()
--   Pre-existing trigger function that bumps last_modified on every UPDATE.
--   SECURITY DEFINER + empty search_path matches the
--   `fix_update_last_modified_search_path` hardening migration applied to
--   prod on 2025-10-23.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.update_last_modified()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  NEW.last_modified = NOW();
  RETURN NEW;
END;
$function$;

-- =============================================================================
-- Table: pins
--   Column order, types, defaults, and the generated `location` expression
--   match prod exactly as of 2026-05-16. The name-length CHECK is added
--   by 007_pin_name_length.sql, not here.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.pins (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  longitude                double precision NOT NULL,
  latitude                 double precision NOT NULL,
  location                 geometry GENERATED ALWAYS AS
                             (ST_SetSRID(ST_MakePoint(longitude, latitude), 4326))
                             STORED,
  status                   integer NOT NULL,
  photo_uri                text,
  notes                    text,
  votes                    integer DEFAULT 0,
  created_by               uuid,
  created_at               timestamptz NOT NULL DEFAULT now(),
  last_modified            timestamptz NOT NULL DEFAULT now(),
  name                     text NOT NULL,
  restriction_tag          public.restriction_tag_type,
  has_security_screening   boolean NOT NULL DEFAULT false,
  has_posted_signage       boolean NOT NULL DEFAULT false
);

-- =============================================================================
-- Indexes on pins
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_pins_created_at    ON public.pins (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_pins_created_by    ON public.pins (created_by);
CREATE INDEX IF NOT EXISTS idx_pins_last_modified ON public.pins (last_modified DESC);
CREATE INDEX IF NOT EXISTS idx_pins_location      ON public.pins USING GIST (location);
CREATE INDEX IF NOT EXISTS idx_pins_name          ON public.pins (name);
CREATE INDEX IF NOT EXISTS idx_pins_status        ON public.pins (status);

-- =============================================================================
-- Trigger: set_last_modified on pins
-- =============================================================================

DROP TRIGGER IF EXISTS set_last_modified ON public.pins;
CREATE TRIGGER set_last_modified
  BEFORE UPDATE ON public.pins
  FOR EACH ROW
  EXECUTE FUNCTION public.update_last_modified();

-- =============================================================================
-- Row-level security on pins
--   Policy names match prod exactly (matters for migration 008's RLS-aware
--   tweaks and for any future DROP POLICY IF EXISTS calls).
-- =============================================================================

ALTER TABLE public.pins ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Pins are viewable by everyone" ON public.pins;
CREATE POLICY "Pins are viewable by everyone" ON public.pins
  FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "Authenticated users can insert pins" ON public.pins;
CREATE POLICY "Authenticated users can insert pins" ON public.pins
  FOR INSERT
  WITH CHECK (auth.uid() = created_by);

DROP POLICY IF EXISTS "Users can update any pin" ON public.pins;
CREATE POLICY "Users can update any pin" ON public.pins
  FOR UPDATE
  USING (auth.role() = 'authenticated'::text)
  WITH CHECK (auth.role() = 'authenticated'::text);

DROP POLICY IF EXISTS "Authenticated users can delete any pin" ON public.pins;
CREATE POLICY "Authenticated users can delete any pin" ON public.pins
  FOR DELETE
  USING (auth.role() = 'authenticated'::text);
