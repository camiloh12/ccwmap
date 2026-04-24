-- 005_pin_reports.sql
-- Receives user-submitted reports on pins. No SELECT policy is defined --
-- rows are only read by the service role (via the send-moderation-email
-- webhook payload, or manually in Supabase Studio). This is intentional:
-- reports are private to moderators.

CREATE TABLE IF NOT EXISTS pin_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pin_id UUID NOT NULL REFERENCES pins(id) ON DELETE CASCADE,
  reporter_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  reason TEXT NOT NULL CHECK (reason IN ('INACCURATE','OFFENSIVE','SPAM','OTHER')),
  note TEXT CHECK (char_length(note) <= 500),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE pin_reports ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "pin_reports_auth_insert" ON pin_reports;
CREATE POLICY "pin_reports_auth_insert" ON pin_reports
  FOR INSERT WITH CHECK (auth.role() = 'authenticated');
-- Deliberately no SELECT/UPDATE/DELETE policies -- service role only.
