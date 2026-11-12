-- 014_pin_report_resolution.sql
-- Database half of the 0.9.0 "Report a problem" feature: report reasons for
-- imported pins, a snapshot of the pin on every report, report outcomes, a
-- per-account report limit, a do-not-import list, and the function that
-- resolves a report.
--
-- Additive: apps before 0.9.0 keep sending INACCURATE / OFFENSIVE / SPAM /
-- OTHER on user pins and those inserts still work.
--
-- Why the pin_reports -> pins foreign key is dropped (spec 4.3): the key was
-- ON DELETE CASCADE, so removing a pin silently deleted its reports. Reports
-- must outlive the pin: the resolver removes imported pins and the health
-- check and moderators need the report afterwards. Each report therefore
-- carries its own snapshot of the pin (pin_* columns), filled by a trigger at
-- insert time. pin_id stays as a plain column.
--
-- Timestamps: resolve_pin_report writes the pin_deletions row (through the
-- existing record_pin_deletion trigger, which uses now()) and the reports'
-- resolved_at (also now()) in one transaction, so both carry the same
-- timestamp. The daily health check relies on that equality to tell an
-- intentional report-driven removal from an unexplained deletion.
--
-- Idempotent (IF NOT EXISTS / CREATE OR REPLACE / DROP ... IF EXISTS) and
-- transaction-safe.

-- =============================================================================
-- 1. New pin_reports columns: pin snapshot and outcome
-- =============================================================================

ALTER TABLE pin_reports
  ADD COLUMN IF NOT EXISTS pin_created_by         UUID,
  ADD COLUMN IF NOT EXISTS pin_source             TEXT,
  ADD COLUMN IF NOT EXISTS pin_source_external_id TEXT,
  ADD COLUMN IF NOT EXISTS pin_name               TEXT,
  ADD COLUMN IF NOT EXISTS pin_latitude           DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS pin_longitude          DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS pin_restriction_tag    TEXT,
  ADD COLUMN IF NOT EXISTS pin_confidence         TEXT,
  ADD COLUMN IF NOT EXISTS pin_legal_citation     TEXT,
  ADD COLUMN IF NOT EXISTS resolved_at            TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS resolution             TEXT,
  ADD COLUMN IF NOT EXISTS moved_to_latitude      DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS moved_to_longitude     DOUBLE PRECISION;

ALTER TABLE pin_reports DROP CONSTRAINT IF EXISTS pin_reports_resolution_check;
ALTER TABLE pin_reports ADD CONSTRAINT pin_reports_resolution_check
  CHECK (resolution IN ('removed','moved','dismissed'));

ALTER TABLE pin_reports DROP CONSTRAINT IF EXISTS pin_reports_resolution_consistent;
ALTER TABLE pin_reports ADD CONSTRAINT pin_reports_resolution_consistent
  CHECK ((resolved_at IS NULL) = (resolution IS NULL));

-- =============================================================================
-- 2. Reasons. OTHER serves both user pins and imported pins.
-- =============================================================================

ALTER TABLE pin_reports DROP CONSTRAINT IF EXISTS pin_reports_reason_check;
ALTER TABLE pin_reports ADD CONSTRAINT pin_reports_reason_check
  CHECK (reason IN ('INACCURATE','OFFENSIVE','SPAM','OTHER',
                    'CLOSED','WRONG_LOCATION','NOT_CATEGORY','DUPLICATE'));

-- =============================================================================
-- 3. Reports outlive their pin (see header)
-- =============================================================================

ALTER TABLE pin_reports DROP CONSTRAINT IF EXISTS pin_reports_pin_id_fkey;

-- =============================================================================
-- 4. Backfill the snapshot for reports that predate this migration
-- =============================================================================

UPDATE pin_reports r
SET pin_created_by         = p.created_by,
    pin_source             = p.source,
    pin_source_external_id = p.source_external_id,
    pin_name               = p.name,
    pin_latitude           = p.latitude,
    pin_longitude          = p.longitude,
    pin_restriction_tag    = p.restriction_tag::text,
    pin_confidence         = p.confidence,
    pin_legal_citation     = p.legal_citation
FROM pins p
WHERE r.pin_id = p.id
  AND r.pin_name IS NULL;

-- =============================================================================
-- 5. One open report per account per pin: close older duplicates first so the
--    unique index below can be built. Keeps the newest.
-- =============================================================================

UPDATE pin_reports
SET resolved_at = now(),
    resolution  = 'dismissed'
WHERE id IN (
  SELECT id FROM (
    SELECT id,
           row_number() OVER (PARTITION BY pin_id, reporter_id
                              ORDER BY created_at DESC, id DESC) AS rn
    FROM pin_reports
    WHERE resolved_at IS NULL AND reporter_id IS NOT NULL
  ) ranked
  WHERE rn > 1
);

-- =============================================================================
-- 6. Indexes
-- =============================================================================

CREATE UNIQUE INDEX IF NOT EXISTS pin_reports_one_open_per_reporter
  ON pin_reports (pin_id, reporter_id)
  WHERE resolved_at IS NULL AND reporter_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS pin_reports_reporter_created_idx
  ON pin_reports (reporter_id, created_at);

-- =============================================================================
-- 7. BEFORE INSERT trigger: reporter identity, limit, snapshot, no outcome
--
--    SECURITY DEFINER because a signed-in user has no SELECT on pin_reports
--    (needed for the limit count). Inside a SECURITY DEFINER function
--    current_user is the function owner, so the caller is identified by the
--    JWT role (auth.role()) instead. The service role (the importer, the
--    resolver) and direct postgres inserts are not forced to a reporter.
-- =============================================================================

CREATE OR REPLACE FUNCTION pin_reports_before_insert() RETURNS TRIGGER AS $$
DECLARE
  v_pin pins%ROWTYPE;
  v_recent INT;
BEGIN
  -- 1. A signed-in user is always the reporter, whatever the client sent.
  IF auth.role() = 'authenticated' THEN
    NEW.reporter_id := auth.uid();
  END IF;

  -- Always stamp the time here: a client-supplied created_at would let a
  -- user backdate reports out of the 24-hour window below.
  NEW.created_at := now();

  -- 2. At most 10 reports per account per 24 hours.
  IF NEW.reporter_id IS NOT NULL THEN
    SELECT count(*) INTO v_recent
    FROM pin_reports
    WHERE reporter_id = NEW.reporter_id
      AND created_at > now() - interval '24 hours';
    IF v_recent >= 10 THEN
      RAISE EXCEPTION 'report_limit_exceeded: at most 10 reports per 24 hours'
        USING ERRCODE = 'P0001';
    END IF;
  END IF;

  -- 3. Snapshot the pin, overwriting anything the client sent.
  SELECT * INTO v_pin FROM pins WHERE id = NEW.pin_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'pin_not_found' USING ERRCODE = 'P0002';
  END IF;
  NEW.pin_created_by         := v_pin.created_by;
  NEW.pin_source             := v_pin.source;
  NEW.pin_source_external_id := v_pin.source_external_id;
  NEW.pin_name               := v_pin.name;
  NEW.pin_latitude           := v_pin.latitude;
  NEW.pin_longitude          := v_pin.longitude;
  NEW.pin_restriction_tag    := v_pin.restriction_tag::text;
  NEW.pin_confidence         := v_pin.confidence;
  NEW.pin_legal_citation     := v_pin.legal_citation;

  -- 4. A new report is always open.
  NEW.resolved_at        := NULL;
  NEW.resolution         := NULL;
  NEW.moved_to_latitude  := NULL;
  NEW.moved_to_longitude := NULL;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS pin_reports_before_insert_trigger ON pin_reports;
CREATE TRIGGER pin_reports_before_insert_trigger
  BEFORE INSERT ON pin_reports
  FOR EACH ROW
  EXECUTE FUNCTION pin_reports_before_insert();

-- =============================================================================
-- 8. import_suppressions: the do-not-import list. Read by the importer
--    (service role). No policies, no access for app roles.
-- =============================================================================

CREATE TABLE IF NOT EXISTS import_suppressions (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source             TEXT NOT NULL,
  source_external_id TEXT NOT NULL,
  name               TEXT,
  latitude           DOUBLE PRECISION,
  longitude          DOUBLE PRECISION,
  report_id          UUID,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (source, source_external_id)
);

ALTER TABLE import_suppressions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON import_suppressions FROM anon, authenticated;

-- =============================================================================
-- 9. resolve_pin_report: called by the resolve workflow with the service-role
--    key. SECURITY INVOKER (runs as service_role), so row security and the
--    013 triggers see the real caller. Never returns the report's note or
--    reporter.
-- =============================================================================

CREATE OR REPLACE FUNCTION resolve_pin_report(
  p_report_id uuid,
  p_action    text,
  p_latitude  double precision DEFAULT NULL,
  p_longitude double precision DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  sys constant uuid := '81775f8b-1a6a-47d6-b793-e9ab7e38634e';
  rep         pin_reports%ROWTYPE;
  v_pin       pins%ROWTYPE;
  v_found     boolean;
  v_closed    int;
  v_deleted   boolean := false;
  v_name      text;
  v_source    text;
  v_ext       text;
  v_lat       double precision;
  v_lng       double precision;
BEGIN
  SELECT * INTO rep FROM pin_reports WHERE id = p_report_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'report_not_found' USING ERRCODE = 'P0001';
  END IF;
  IF rep.resolved_at IS NOT NULL THEN
    RAISE EXCEPTION 'report_already_resolved' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_pin FROM pins WHERE id = rep.pin_id;
  v_found := FOUND;

  IF COALESCE(v_pin.created_by, rep.pin_created_by) IS DISTINCT FROM sys THEN
    RAISE EXCEPTION 'not_an_imported_pin' USING ERRCODE = 'P0001';
  END IF;

  IF p_action NOT IN ('remove', 'move', 'dismiss') THEN
    RAISE EXCEPTION 'unknown_action' USING ERRCODE = 'P0001';
  END IF;

  -- The pin's identity: live row, or the snapshot when the pin is gone.
  v_name   := CASE WHEN v_found THEN v_pin.name ELSE rep.pin_name END;
  v_source := CASE WHEN v_found THEN v_pin.source ELSE rep.pin_source END;
  v_ext    := CASE WHEN v_found THEN v_pin.source_external_id
                   ELSE rep.pin_source_external_id END;
  v_lat    := CASE WHEN v_found THEN v_pin.latitude ELSE rep.pin_latitude END;
  v_lng    := CASE WHEN v_found THEN v_pin.longitude ELSE rep.pin_longitude END;

  IF p_action = 'remove' THEN
    IF v_ext IS NULL OR v_source IS NULL THEN
      RAISE EXCEPTION 'missing_source_external_id' USING ERRCODE = 'P0001';
    END IF;

    INSERT INTO import_suppressions
      (source, source_external_id, name, latitude, longitude, report_id)
    VALUES (v_source, v_ext, v_name, v_lat, v_lng, rep.id)
    ON CONFLICT (source, source_external_id) DO NOTHING;

    DELETE FROM pins WHERE id = rep.pin_id;
    v_deleted := FOUND;

    -- Every open report on the pin is settled by its removal.
    UPDATE pin_reports
    SET resolved_at = now(), resolution = 'removed'
    WHERE pin_id = rep.pin_id AND resolved_at IS NULL;
    GET DIAGNOSTICS v_closed = ROW_COUNT;

  ELSIF p_action = 'move' THEN
    IF p_latitude IS NULL OR p_longitude IS NULL THEN
      RAISE EXCEPTION 'move_needs_coordinates' USING ERRCODE = 'P0001';
    END IF;
    IF p_latitude  NOT BETWEEN 24.396308 AND 49.384358
       OR p_longitude NOT BETWEEN -125.0 AND -66.93457 THEN
      RAISE EXCEPTION 'coordinates_outside_continental_us' USING ERRCODE = 'P0001';
    END IF;
    IF NOT v_found THEN
      RAISE EXCEPTION 'pin_not_found' USING ERRCODE = 'P0001';
    END IF;

    -- A service-role write never sets user_modified by itself (013), so set
    -- it here: the importer must not move the pin back.
    UPDATE pins
    SET latitude = p_latitude, longitude = p_longitude, user_modified = true
    WHERE id = rep.pin_id;

    UPDATE pin_reports
    SET resolved_at = now(), resolution = 'moved',
        moved_to_latitude = p_latitude, moved_to_longitude = p_longitude
    WHERE pin_id = rep.pin_id AND resolved_at IS NULL AND reason = rep.reason;
    GET DIAGNOSTICS v_closed = ROW_COUNT;

    v_lat := p_latitude;
    v_lng := p_longitude;

  ELSE -- dismiss: the pin is left alone and may already be gone.
    UPDATE pin_reports
    SET resolved_at = now(), resolution = 'dismissed'
    WHERE pin_id = rep.pin_id AND resolved_at IS NULL AND reason = rep.reason;
    GET DIAGNOSTICS v_closed = ROW_COUNT;
  END IF;

  RETURN jsonb_build_object(
    'report_id',      rep.id,
    'action',         p_action,
    'pin_id',         rep.pin_id,
    'pin_name',       v_name,
    'pin_source',     v_source,
    'latitude',       v_lat,
    'longitude',      v_lng,
    'pin_deleted',    v_deleted,
    'closed_reports', v_closed
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION resolve_pin_report(uuid, text, double precision, double precision)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION resolve_pin_report(uuid, text, double precision, double precision)
  TO service_role;
