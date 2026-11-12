-- Verification probe for 014_pin_report_resolution.sql.
--
-- Safe to run on staging or prod: every change happens inside one DO block
-- that ends with RAISE EXCEPTION, so the whole block rolls back. The result
-- is the error message ("PROBE ...").
--
-- Needs only a database with imported (system-owned) pins that have a
-- source_external_id (at least 15) and at least one signed-in user. It picks
-- its pins and user itself, and first clears any reports on those pins and
-- any reports by that user (inside the rolled-back transaction) so the
-- 10-per-24-hours count starts at zero.
--
-- Paste into the project's SQL editor and run. Expected after 014:
--   R1 reporter=self snapshot=from_pin resolved=null
--   R2 dup=23505
--   R4 missing=pin_not_found
--   R3 limit=report_limit_exceeded stamped=t
--   R5 removed: pin_gone=t entry=1 closed=<n>
--   R5 again=report_already_resolved
--   R6 swapped=coordinates_outside_continental_us
--   R6 moved um=t lat=<new>
--   R7 dismissed closed=1 other_open=1
--   R8 pin_reports=denied import_suppressions=denied resolve=denied
--   R9 report_survives=t pin_id_kept=t
--   R10 closed_ok=t bogus=23514
-- (Cases print in the order they run: R1, R2, R4, R3, R5, R6, R7, R8, R9, R10.)
--
-- Cases: R1 a signed-in user's insert gets reporter_id and the snapshot from
-- the server, whatever the client sent; R2 one open report per account per
-- pin; R3 at most 10 reports per account per 24 h; R4 a report on a pin that
-- doesn't exist is refused; R5 resolve_pin_report 'remove' deletes the pin,
-- writes the do-not-import entry and closes the reports, and a second call
-- is refused; R6 'move' rejects swapped coordinates, then moves the pin and
-- marks it user_modified; R7 'dismiss' closes only the reports with the same
-- reason; R8 signed-in users can't read reports or suppressions or call the
-- function; R9 deleting a pin keeps its report; R10 the CLOSED reason is
-- accepted and an unknown one is refused.
DO $$
DECLARE
  sys   constant uuid := '81775f8b-1a6a-47d6-b793-e9ab7e38634e';
  usr   uuid;
  ids   uuid[];
  rid   uuid;
  r1    uuid := gen_random_uuid();
  r6    uuid := gen_random_uuid();
  r7a   uuid := gen_random_uuid();
  r7b   uuid := gen_random_uuid();
  r9    uuid := gen_random_uuid();
  i     int;
  st    text;
  msg   text;
  n     bigint;
  rec   record;
  res   jsonb;
  src   text;
  ext   text;
  r     text := '';
  d1    text; d2 text; d3 text;
BEGIN
  SELECT id INTO usr FROM auth.users WHERE id <> sys ORDER BY created_at LIMIT 1;
  SELECT array_agg(id ORDER BY id) INTO ids FROM (
    SELECT id FROM pins
    WHERE created_by = sys AND source_external_id IS NOT NULL
      AND NOT user_modified
    ORDER BY id LIMIT 15) s;

  -- Setup (postgres): start from a clean slate for these pins and this user.
  DELETE FROM pin_reports WHERE pin_id = ANY (ids) OR reporter_id = usr;

  -- ---- R1: user insert; client-supplied reporter, snapshot, outcome ignored
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', usr, 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;
  INSERT INTO pin_reports (id, pin_id, reporter_id, reason,
      pin_created_by, pin_source, pin_source_external_id, pin_name,
      pin_latitude, pin_longitude, pin_restriction_tag, pin_confidence,
      pin_legal_citation, resolved_at, resolution,
      moved_to_latitude, moved_to_longitude)
    VALUES (r1, ids[1], gen_random_uuid(), 'CLOSED',
      gen_random_uuid(), 'fake', 'fake', 'FAKE NAME',
      0, 0, 'FAKE', 'low',
      'fake', now(), 'removed',
      1, 1);
  RESET ROLE;
  SELECT rr.*, p.name AS p_name, p.latitude AS p_lat, p.longitude AS p_lng,
         p.created_by AS p_cb, p.source AS p_src,
         p.source_external_id AS p_ext, p.restriction_tag::text AS p_tag,
         p.confidence AS p_conf, p.legal_citation AS p_cit
    INTO rec
    FROM pin_reports rr JOIN pins p ON p.id = rr.pin_id WHERE rr.id = r1;
  src := rec.p_src;
  ext := rec.p_ext;
  r := r || format('R1 reporter=%s snapshot=%s resolved=%s; ',
    CASE WHEN rec.reporter_id = usr THEN 'self' ELSE 'OTHER' END,
    CASE WHEN rec.pin_name = rec.p_name
           AND rec.pin_latitude = rec.p_lat
           AND rec.pin_longitude = rec.p_lng
           AND rec.pin_created_by = rec.p_cb
           AND rec.pin_source = rec.p_src
           AND rec.pin_source_external_id IS NOT DISTINCT FROM rec.p_ext
           AND rec.pin_restriction_tag IS NOT DISTINCT FROM rec.p_tag
           AND rec.pin_confidence IS NOT DISTINCT FROM rec.p_conf
           AND rec.pin_legal_citation IS NOT DISTINCT FROM rec.p_cit
         THEN 'from_pin' ELSE 'CLIENT_VALUES' END,
    CASE WHEN rec.resolved_at IS NULL AND rec.resolution IS NULL
           AND rec.moved_to_latitude IS NULL AND rec.moved_to_longitude IS NULL
         THEN 'null' ELSE 'SET' END);

  -- ---- R2: same user, second open report on the same pin
  st := 'none';
  SET LOCAL ROLE authenticated;
  BEGIN
    INSERT INTO pin_reports (pin_id, reason) VALUES (ids[1], 'DUPLICATE');
  EXCEPTION WHEN OTHERS THEN
    st := SQLSTATE;
  END;
  RESET ROLE;
  r := r || format('R2 dup=%s; ', st);

  -- ---- R4: report on a pin that doesn't exist
  st := 'none';
  SET LOCAL ROLE authenticated;
  BEGIN
    INSERT INTO pin_reports (pin_id, reason) VALUES (gen_random_uuid(), 'CLOSED');
  EXCEPTION WHEN OTHERS THEN
    st := CASE WHEN SQLERRM LIKE 'pin_not_found%' THEN 'pin_not_found'
               ELSE SQLSTATE || ' ' || SQLERRM END;
  END;
  RESET ROLE;
  r := r || format('R4 missing=%s; ', st);

  -- ---- R3: 9 more reports on 9 more pins (10 in total), then an 11th
  SET LOCAL ROLE authenticated;
  FOR i IN 2..10 LOOP
    -- backdated by the client: the trigger must restamp, so they still count
    INSERT INTO pin_reports (pin_id, reason, created_at)
      VALUES (ids[i], 'INACCURATE', now() - interval '2 days');
  END LOOP;
  st := 'none';
  BEGIN
    INSERT INTO pin_reports (pin_id, reason) VALUES (ids[11], 'INACCURATE');
  EXCEPTION WHEN OTHERS THEN
    st := CASE WHEN SQLERRM LIKE 'report_limit_exceeded%' THEN 'report_limit_exceeded'
               ELSE SQLSTATE || ' ' || SQLERRM END;
  END;
  RESET ROLE;
  SELECT count(*) INTO n FROM pin_reports
    WHERE reporter_id = usr AND created_at = now();
  r := r || format('R3 limit=%s stamped=%s; ', st, n = 10);

  -- ---- R5: importer-side remove, then remove again (service_role)
  PERFORM set_config('request.jwt.claims',
    json_build_object('role', 'service_role')::text, true);
  SET LOCAL ROLE service_role;
  res := resolve_pin_report(r1, 'remove');
  SELECT count(*) INTO n FROM import_suppressions
    WHERE source = src AND source_external_id = ext;
  r := r || format('R5 removed: pin_gone=%s entry=%s closed=%s; ',
    NOT EXISTS (SELECT 1 FROM pins WHERE id = ids[1]), n,
    res ->> 'closed_reports');
  st := 'none';
  BEGIN
    PERFORM resolve_pin_report(r1, 'remove');
  EXCEPTION WHEN OTHERS THEN
    st := SQLERRM;
  END;
  r := r || format('R5 again=%s; ', st);

  -- ---- R6: move. Swapped coordinates first, then a valid point.
  INSERT INTO pin_reports (id, pin_id, reason) VALUES (r6, ids[14], 'WRONG_LOCATION');
  st := 'none';
  BEGIN
    PERFORM resolve_pin_report(r6, 'move', -95.2, 29.7);
  EXCEPTION WHEN OTHERS THEN
    st := SQLERRM;
  END;
  r := r || format('R6 swapped=%s; ', st);
  PERFORM resolve_pin_report(r6, 'move', 29.7604, -95.3698);
  SELECT user_modified, latitude INTO rec FROM pins WHERE id = ids[14];
  r := r || format('R6 moved um=%s lat=%s; ', rec.user_modified, rec.latitude);

  -- ---- R7: dismiss one of two open reports with different reasons
  INSERT INTO pin_reports (id, pin_id, reason) VALUES (r7a, ids[12], 'WRONG_LOCATION');
  INSERT INTO pin_reports (id, pin_id, reason) VALUES (r7b, ids[12], 'CLOSED');
  res := resolve_pin_report(r7a, 'dismiss');
  SELECT count(*) INTO n FROM pin_reports
    WHERE pin_id = ids[12] AND resolved_at IS NULL AND reason = 'CLOSED';
  r := r || format('R7 dismissed closed=%s other_open=%s; ',
    res ->> 'closed_reports', n);
  RESET ROLE;

  -- ---- R8: a signed-in user can't read reports/suppressions or resolve
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', usr, 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;
  d1 := 'READABLE'; d2 := 'READABLE'; d3 := 'CALLABLE';
  BEGIN
    SELECT count(*) INTO n FROM pin_reports;
    IF n = 0 THEN d1 := 'denied'; END IF;
  EXCEPTION WHEN insufficient_privilege THEN d1 := 'denied';
  END;
  BEGIN
    SELECT count(*) INTO n FROM import_suppressions;
    IF n = 0 THEN d2 := 'denied'; END IF;
  EXCEPTION WHEN insufficient_privilege THEN d2 := 'denied';
  END;
  BEGIN
    PERFORM resolve_pin_report(r7b, 'dismiss');
  EXCEPTION WHEN insufficient_privilege THEN d3 := 'denied';
            WHEN OTHERS THEN d3 := 'CALLABLE ' || SQLERRM;
  END;
  RESET ROLE;
  r := r || format('R8 pin_reports=%s import_suppressions=%s resolve=%s; ',
    d1, d2, d3);

  -- ---- R9: deleting a pin keeps the report (FK dropped)
  PERFORM set_config('request.jwt.claims',
    json_build_object('role', 'service_role')::text, true);
  SET LOCAL ROLE service_role;
  INSERT INTO pin_reports (id, pin_id, reason) VALUES (r9, ids[13], 'CLOSED');
  DELETE FROM pins WHERE id = ids[13];
  RESET ROLE;
  SELECT pin_id INTO rid FROM pin_reports WHERE id = r9;
  r := r || format('R9 report_survives=%s pin_id_kept=%s; ',
    FOUND, rid IS NOT DISTINCT FROM ids[13]);

  -- ---- R10: CLOSED accepted, an unknown reason refused
  SET LOCAL ROLE service_role;
  st := 'none';
  BEGIN
    INSERT INTO pin_reports (pin_id, reason) VALUES (ids[15], 'CLOSED');
    n := 1;
  EXCEPTION WHEN OTHERS THEN
    n := 0;
  END;
  BEGIN
    INSERT INTO pin_reports (pin_id, reason) VALUES (ids[15], 'BOGUS');
  EXCEPTION WHEN OTHERS THEN
    st := SQLSTATE;
  END;
  RESET ROLE;
  r := r || format('R10 closed_ok=%s bogus=%s', n = 1, st);

  RAISE EXCEPTION 'PROBE %', r;
END $$;
