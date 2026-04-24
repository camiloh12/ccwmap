-- 006_blocked_users.sql
-- Block-by-user relationship. The UI framing is "block creator of this
-- pin" (pin creator identity is never surfaced directly), but the
-- relationship table is user-to-user so a single block hides every pin
-- that user ever created.

CREATE TABLE IF NOT EXISTS blocked_users (
  blocker_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  blocked_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (blocker_id, blocked_id),
  CHECK (blocker_id <> blocked_id)
);

ALTER TABLE blocked_users ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "blocked_users_own_all" ON blocked_users;
CREATE POLICY "blocked_users_own_all" ON blocked_users
  FOR ALL
  USING (auth.uid() = blocker_id)
  WITH CHECK (auth.uid() = blocker_id);
