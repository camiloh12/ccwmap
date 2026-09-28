-- Daily health check metrics: one row holding one JSON object.
-- Read by ci/health_check.py (run by .github/workflows/health-check.yml),
-- which runs it in a read-only session with a statement_timeout. Every
-- top-level key is one of health_check.py's METRIC_KEYS; the ci tests keep
-- the two in sync. "Imported" = owned by the system user the importer
-- writes as.
-- Spec: docs/superpowers/specs/2026-09-27-daily-health-check-design.md
WITH sys AS (
  SELECT '81775f8b-1a6a-47d6-b793-e9ab7e38634e'::uuid AS id
),
imported AS (
  SELECT p.id, p.name, p.source, p.status, p.confidence, p.user_modified,
         p.last_modified, p.source_orphaned_at,
         p.legal_citation_verified_date
  FROM pins p, sys
  WHERE p.created_by = sys.id
),
-- Statutory pins (confidence 'high') are NO_GUN by law, and 013 keeps
-- signed-in users from changing their status.
flipped AS (
  SELECT id, name, source, status, last_modified
  FROM imported
  WHERE confidence = 'high' AND user_modified AND status <> 2
)
SELECT json_build_object(
  'imported_total', (SELECT count(*) FROM imported),
  'imported_deleted_24h', (SELECT count(*) FROM pin_deletions d, sys
                           WHERE d.original_created_by = sys.id
                             AND d.deleted_at > now() - interval '24 hours'),
  'deletions_24h', (SELECT count(*) FROM pin_deletions
                    WHERE deleted_at > now() - interval '24 hours'),
  'statutory_flipped', (SELECT count(*) FROM flipped),
  'statutory_flipped_sample', (SELECT coalesce(json_agg(json_build_object(
                                   'id', f.id, 'name', f.name,
                                   'source', f.source, 'status', f.status)
                                 ORDER BY f.last_modified DESC), '[]'::json)
                               FROM (SELECT * FROM flipped
                                     ORDER BY last_modified DESC
                                     LIMIT 20) f),
  'imported_user_edits_24h', (SELECT count(*) FROM imported
                              WHERE user_modified
                                AND last_modified > now() - interval '24 hours'),
  'imported_orphaned', (SELECT count(*) FROM imported
                        WHERE source_orphaned_at IS NOT NULL),
  'stale_citations', (SELECT count(*) FROM imported
                      WHERE legal_citation_verified_date
                            < current_date - interval '12 months'),
  'imported_by_source_status', (SELECT coalesce(json_agg(json_build_object(
                                    'source', s.source, 'status', s.status,
                                    'count', s.n)
                                  ORDER BY s.source, s.status), '[]'::json)
                                FROM (SELECT source, status, count(*) AS n
                                      FROM imported
                                      GROUP BY source, status) s),
  'user_pins_total', (SELECT count(*) FROM pins p, sys
                      WHERE p.created_by IS DISTINCT FROM sys.id),
  'imported_user_corrected', (SELECT count(*) FROM imported
                              WHERE user_modified),
  'imported_reports_7d', (SELECT count(*) FROM pin_reports r
                          JOIN imported i ON i.id = r.pin_id
                          WHERE r.created_at > now() - interval '7 days')
);
