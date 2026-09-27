-- 013_lock_statutory_system_pins.sql
-- Signed-in users can no longer change the legal fields of statutory
-- pre-populated pins, and a save that changes nothing no longer marks a pin
-- user_modified.
--
-- Why: 012 (BUG-006) let any signed-in user edit any system pin. That's right
-- for facts users can see (name, posted signage, security screening), but it
-- also let one user flip a statutory NO_GUN pin (a school, courthouse,
-- federal building or secure airport) to ALLOWED for everyone. A wrong
-- "allowed" can put a carrier in a prohibited place; a wrong "no carry" only
-- costs an inconvenience. Owner decision 2026-09-27: lock them. Users report
-- problems with those pins instead (0.9.0 "Report a problem").
--
-- 1. lock_statutory_fields() — for rows owned by the system user with
--    confidence = 'high' (every state-law cell with a categorical statutory
--    prohibition; OSM bars are 'medium' and stay editable), a signed-in
--    user's UPDATE keeps the existing status, restriction_tag, latitude and
--    longitude. The rest of the save goes through.
--
--    It keeps the old values instead of raising because the app sends the
--    full row on every save (SupabasePinDto.toJsonForUpdate). Raising would
--    reject innocent edits whenever the app's cached copy is stale, and app
--    versions before 0.9.0 never surface a rejected save anyway (the sync
--    queue records the error and drops the op), so to those users a
--    rejection and a kept value look the same. 0.9.0 shows these fields as
--    fixed, so the app never offers a change that won't save.
--
--    Scoped to current_user = 'authenticated'. service_role (the importer)
--    and postgres (dashboard / migrations) are unaffected. anon has no
--    UPDATE grant. users can't change created_by or confidence (008 §8
--    column grants), so they can't unlock a row.
--
-- 2. set_user_modified() — now marks user_modified only when a
--    user-editable column (the 008 §8 grant list) actually changed. Before,
--    any non-service_role UPDATE marked it, so a no-op save (including a
--    status flip that (1) discards) froze the pin against future imports.
--    Side effect: a postgres UPDATE that only resets user_modified now
--    sticks.
--
-- Trigger order: PostgreSQL fires BEFORE triggers of the same event in name
-- order, so lock_statutory_fields_trigger runs before
-- set_user_modified_trigger and set_last_modified, and the change check in
-- (2) sees the already-restored values.
--
-- Idempotent (CREATE OR REPLACE / DROP TRIGGER IF EXISTS), transaction-safe.

CREATE OR REPLACE FUNCTION lock_statutory_fields() RETURNS TRIGGER AS $$
BEGIN
  IF current_user = 'authenticated'
     AND OLD.created_by = '81775f8b-1a6a-47d6-b793-e9ab7e38634e'::uuid
     AND OLD.confidence = 'high' THEN
    NEW.status          := OLD.status;
    NEW.restriction_tag := OLD.restriction_tag;
    NEW.latitude        := OLD.latitude;
    NEW.longitude       := OLD.longitude;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS lock_statutory_fields_trigger ON pins;
CREATE TRIGGER lock_statutory_fields_trigger
  BEFORE UPDATE ON pins
  FOR EACH ROW
  EXECUTE FUNCTION lock_statutory_fields();

CREATE OR REPLACE FUNCTION set_user_modified() RETURNS TRIGGER AS $$
BEGIN
  IF current_user <> 'service_role'
     AND (NEW.name, NEW.latitude, NEW.longitude, NEW.status,
          NEW.restriction_tag, NEW.has_security_screening,
          NEW.has_posted_signage, NEW.notes, NEW.photo_uri, NEW.votes)
         IS DISTINCT FROM
         (OLD.name, OLD.latitude, OLD.longitude, OLD.status,
          OLD.restriction_tag, OLD.has_security_screening,
          OLD.has_posted_signage, OLD.notes, OLD.photo_uri, OLD.votes) THEN
    NEW.user_modified := true;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
