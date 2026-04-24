-- 004_user_agreements.sql
-- Tracks per-user acceptance of a versioned EULA. Apple Guideline 1.2
-- requires enforced acceptance of the community guidelines before a user
-- can post UGC; the row-per-version design lets us re-prompt existing
-- users after material wording changes.

CREATE TABLE IF NOT EXISTS user_agreements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  agreement_version INTEGER NOT NULL,
  accepted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, agreement_version)
);

ALTER TABLE user_agreements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "user_agreements_own_insert" ON user_agreements;
CREATE POLICY "user_agreements_own_insert" ON user_agreements
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "user_agreements_own_select" ON user_agreements;
CREATE POLICY "user_agreements_own_select" ON user_agreements
  FOR SELECT USING (auth.uid() = user_id);
