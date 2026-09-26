-- 012_system_pins_user_correctable.sql
-- BUG-006 fix. Lets signed-in users correct (UPDATE) pre-populated system
-- pins while still blocking them from deleting those pins, and makes the
-- "deny the system user" hardening actually key on the system user's session.
--
-- Root cause: migration 008 §9 created three RESTRICTIVE policies meant to
-- stop a session *logged in as* the system user (spec §3 "Hardening": "even
-- if the password leaks, an authenticated session can only read"). But the
-- UPDATE/DELETE policies tested the ROW's creator —
--   USING (created_by IS DISTINCT FROM '<system uuid>')
-- — so they rejected EVERY signed-in user's UPDATE/DELETE of every imported
-- pin. Postgrest reports that as success with 0 rows affected, so app edits
-- appeared to save and then silently reverted on the next viewport fetch.
-- It also made the spec's user-correction path dead code: the
-- set_user_modified trigger could never fire on a system pin, so the
-- importer's "skip user_modified rows" branch could never protect a
-- correction.
--
-- New policies (same names, re-created):
--   INSERT  — no one may insert a row attributed to the system user, and
--             the system user's session may not insert at all.
--   UPDATE  — only the system user's SESSION is denied. Any other signed-in
--             user may edit any pin, system pins included (the permissive
--             "Users can update any pin" policy + 008 §8's column-level
--             grants still apply — provenance columns and created_by are not
--             updatable by `authenticated`, so a correction can't re-attribute
--             or forge provenance). The old WITH CHECK on created_by is
--             dropped: an edited system pin keeps created_by = system, so it
--             would reject exactly the corrections we now allow.
--   DELETE  — system-owned pins stay undeletable by users (owner decision
--             2026-09-26: "edit yes, delete no" — the importer doesn't read
--             pin_deletions and pin ids are random, so a deleted system pin
--             would simply be re-inserted by the next import), and the
--             system user's session may not delete anything.
--
-- service_role (the importer) bypasses RLS entirely; unaffected.
--
-- Idempotent (DROP ... IF EXISTS before CREATE) per docs/dev/STAGING.md.
-- NOTE: re-applying 008 after this re-creates the old row-keyed policies;
-- re-apply 012 afterwards.

DROP POLICY IF EXISTS "deny_system_user_insert" ON pins;
DROP POLICY IF EXISTS "deny_system_user_update" ON pins;
DROP POLICY IF EXISTS "deny_system_user_delete" ON pins;

CREATE POLICY "deny_system_user_insert" ON pins
  AS RESTRICTIVE
  FOR INSERT
  TO authenticated
  WITH CHECK (
    created_by IS DISTINCT FROM '81775f8b-1a6a-47d6-b793-e9ab7e38634e'::uuid
    AND auth.uid() IS DISTINCT FROM '81775f8b-1a6a-47d6-b793-e9ab7e38634e'::uuid
  );

CREATE POLICY "deny_system_user_update" ON pins
  AS RESTRICTIVE
  FOR UPDATE
  TO authenticated
  USING      (auth.uid() IS DISTINCT FROM '81775f8b-1a6a-47d6-b793-e9ab7e38634e'::uuid)
  WITH CHECK (auth.uid() IS DISTINCT FROM '81775f8b-1a6a-47d6-b793-e9ab7e38634e'::uuid);

CREATE POLICY "deny_system_user_delete" ON pins
  AS RESTRICTIVE
  FOR DELETE
  TO authenticated
  USING (
    created_by IS DISTINCT FROM '81775f8b-1a6a-47d6-b793-e9ab7e38634e'::uuid
    AND auth.uid() IS DISTINCT FROM '81775f8b-1a6a-47d6-b793-e9ab7e38634e'::uuid
  );
