-- Verification probe for 013_lock_statutory_system_pins.sql.
--
-- Safe to run on staging or prod: every change happens inside one DO block
-- that ends with RAISE EXCEPTION, so the whole block rolls back. The result
-- is the error message ("PROBE ...").
--
-- Paste into the project's SQL editor and run. Expected after 013:
--   A[stat flip+move] status=2 tag=<unchanged tag> moved=f um=f
--   B[stat rename+flip] status=2 renamed=t um=t
--   E[noop save] um=f
--   C[bar status] status=2 um=t
--   D[user pin] updated_to=<0 or 1>
--   F[service_role] status=1
--   G[postgres] status=0 um=t
-- Before 013, A shows status=0 moved=t um=t and E shows um=t.
--
-- Cases: A/B a signed-in user tries to change a statutory (confidence
-- 'high') system pin; E a save that changes nothing; C/D bar and user pins
-- stay editable; F the importer (service_role) and G an admin (postgres)
-- are unaffected.
DO $$
DECLARE
  sys   constant uuid := '81775f8b-1a6a-47d6-b793-e9ab7e38634e';
  usr   uuid;
  stat1 uuid; stat2 uuid; bar uuid; upin uuid;
  lat0  float8;
  p     record;
  r     text := '';
BEGIN
  SELECT id INTO usr FROM auth.users WHERE id <> sys ORDER BY created_at LIMIT 1;
  SELECT id INTO stat1 FROM pins WHERE created_by = sys AND confidence = 'high'
    AND NOT user_modified ORDER BY id LIMIT 1;
  SELECT id INTO stat2 FROM pins WHERE created_by = sys AND confidence = 'high'
    AND NOT user_modified AND id <> stat1 ORDER BY id LIMIT 1;
  SELECT id INTO bar FROM pins WHERE created_by = sys AND confidence = 'medium'
    AND NOT user_modified ORDER BY id LIMIT 1;
  SELECT id INTO upin FROM pins WHERE created_by <> sys ORDER BY id LIMIT 1;
  SELECT latitude INTO lat0 FROM pins WHERE id = stat1;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', usr, 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;

  -- A: signed-in user flips + moves a statutory pin (nothing else changes)
  UPDATE pins SET status = 0, restriction_tag = NULL,
    latitude = latitude + 0.05, longitude = longitude + 0.05 WHERE id = stat1;
  SELECT status, restriction_tag, latitude <> lat0 AS moved, user_modified
    INTO p FROM pins WHERE id = stat1;
  r := r || format('A[stat flip+move] status=%s tag=%s moved=%s um=%s; ',
    p.status, p.restriction_tag, p.moved, p.user_modified);

  -- B: full-row save that renames a statutory pin and also tries a flip
  UPDATE pins SET name = name || ' (probe)', status = 0 WHERE id = stat2;
  SELECT status, name LIKE '% (probe)' AS renamed, user_modified
    INTO p FROM pins WHERE id = stat2;
  r := r || format('B[stat rename+flip] status=%s renamed=%s um=%s; ',
    p.status, p.renamed, p.user_modified);

  -- E: no-op full-row save on a bar pin
  UPDATE pins SET name = name, status = status WHERE id = bar;
  SELECT user_modified INTO p FROM pins WHERE id = bar;
  r := r || format('E[noop save] um=%s; ', p.user_modified);

  -- C: user raises a bar pin (medium confidence) to NO_GUN
  UPDATE pins SET status = 2 WHERE id = bar;
  SELECT status, user_modified INTO p FROM pins WHERE id = bar;
  r := r || format('C[bar status] status=%s um=%s; ', p.status, p.user_modified);

  -- D: user changes their own/user pin status
  UPDATE pins SET status = CASE WHEN status = 0 THEN 1 ELSE 0 END WHERE id = upin
    RETURNING status INTO p;
  r := r || format('D[user pin] updated_to=%s; ', p.status);

  RESET ROLE;
  -- F: importer (service_role) changes a statutory pin's status
  SET LOCAL ROLE service_role;
  UPDATE pins SET status = 1 WHERE id = stat1;
  SELECT status INTO p FROM pins WHERE id = stat1;
  r := r || format('F[service_role] status=%s; ', p.status);
  RESET ROLE;

  -- G: admin (postgres) changes a statutory pin's status
  UPDATE pins SET status = 0 WHERE id = stat2;
  SELECT status, user_modified INTO p FROM pins WHERE id = stat2;
  r := r || format('G[postgres] status=%s um=%s', p.status, p.user_modified);

  RAISE EXCEPTION 'PROBE %', r;
END $$;
