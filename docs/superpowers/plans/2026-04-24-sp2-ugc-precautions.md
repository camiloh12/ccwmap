# SP-2 — UGC Precautions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement all four required precautions for Apple Guideline 1.2 (user-generated content): EULA acceptance, report mechanism, block mechanism, and name-field constraints — plus the moderation plumbing that lets the developer act on reports within a 24-hour SLA.

**Architecture:** Four Supabase migrations introduce three new server tables (`user_agreements`, `pin_reports`, `blocked_users`) plus a `CHECK` constraint on `pins.name`. A new `send-moderation-email` Supabase Edge Function fan-outs database-webhook payloads into the developer's inbox via Resend. In the app, two new domain repository interfaces (`AgreementsRepository`, `ModerationRepository`) back three new UI surfaces (EULA modal with two modes, ReportPinDialog, Block-user confirmation dialog) plus conditional Report/Block buttons on the existing `PinDialog`. An in-memory `BlocklistService` filters the pin stream client-side so blocked users' pins disappear immediately from the blocker's view. A minimal `ProfanityFilter` + length cap hardens the name field; the report mechanism is the real defense against abuse.

**Tech Stack:** Flutter 3.41.7 / Dart 3.11.5; new packages: `shared_preferences`, `url_launcher`. Supabase Edge Functions (Deno runtime). Resend HTTP API.

**Spec reference:** `docs/superpowers/specs/2026-04-24-ios-rejection-response-design.md` — SP-2 section.

**Dependency on SP-1:** This plan assumes SP-1 is already merged. `AuthViewModel`, `SignInPromptSheet`, and `PinDialog.isReadOnly` are all in use. The EULA retroactive-blocking modal hooks into the same `_AppRoot` introduced in SP-1 Task 3.

---

## File Structure

### New Supabase artifacts (new `supabase/` directory tree)

- `supabase/migrations/004_user_agreements.sql`
- `supabase/migrations/005_pin_reports.sql`
- `supabase/migrations/006_blocked_users.sql`
- `supabase/migrations/007_pin_name_length.sql`
- `supabase/functions/send-moderation-email/index.ts`
- `supabase/functions/send-moderation-email/deno.json` (optional but conventional)
- `supabase/.gitignore` — exclude `.env`, `functions/*/.env.local`

### New Flutter source files

- `lib/core/profanity_filter.dart` — ~40 LOC; `const` wordlist + pure static matching.
- `lib/domain/repositories/agreements_repository.dart` — interface.
- `lib/domain/repositories/moderation_repository.dart` — interface.
- `lib/data/repositories/supabase_agreements_repository.dart` — impl.
- `lib/data/repositories/supabase_moderation_repository.dart` — impl.
- `lib/data/services/blocklist_service.dart` — in-memory set + refresh on auth change.
- `lib/presentation/widgets/eula_modal.dart` — supports two modes: `passiveFirstLaunch` and `retroactiveBlocking`.
- `lib/presentation/widgets/report_pin_dialog.dart` — reason radio + optional note + Submit.

### New test files

- `test/core/profanity_filter_test.dart`
- `test/data/services/blocklist_service_test.dart`
- `test/presentation/widgets/eula_modal_test.dart`
- `test/presentation/widgets/report_pin_dialog_test.dart`
- `test/presentation/widgets/pin_dialog_report_block_test.dart` — PinDialog's conditional Report/Block buttons.
- `test/fakes/fake_agreements_repository.dart`
- `test/fakes/fake_moderation_repository.dart`

### New docs

- `docs/MODERATION.md` — operational playbook for moderation.
- `docs/DEPLOY.md` — manual Edge Function deploy steps.

### Modified files

- `pubspec.yaml` — add `shared_preferences`, `url_launcher`.
- `.gitignore` — add `supabase/functions/*/.env*`.
- `lib/data/datasources/supabase_remote_data_source.dart` — add six methods (`hasAcceptedAgreement`, `recordAgreementAcceptance`, `fetchBlocklist`, `blockUser`, `unblockUser`, `submitPinReport`).
- `lib/data/datasources/remote_data_source_interface.dart` — mirror the six new methods on the interface (if they belong there; otherwise add them to new moderation/agreements data-source interfaces — see Task 10 for the decision).
- `lib/presentation/screens/login_screen.dart` — add EULA checkbox to signup form; gate Submit until checked.
- `lib/presentation/widgets/pin_dialog.dart` — add Report + Block buttons between the "Delete" button and the action-buttons row, gated on `viewerCanReport` (new optional param: owner-aware and auth-aware).
- `lib/presentation/screens/map_screen.dart` — wire new callbacks on `_showPinDialog`; post-block snackbar; blocklist refresh coordination.
- `lib/presentation/viewmodels/map_viewmodel.dart` — apply blocklist filter in pin stream.
- `lib/presentation/viewmodels/auth_viewmodel.dart` — trigger blocklist refresh + retroactive-EULA check on auth state change.
- `lib/main.dart` — inject `AgreementsRepository`, `ModerationRepository`, `BlocklistService` into DI; wire first-launch EULA gate inside `_AppRoot`.
- `test/widget_test.dart` — supply new repositories to `CCWMapApp` (will update in Task 11's fallout).
- `CLAUDE.md` — iteration status.

---

### Task 1: Add dependencies

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add `shared_preferences` and `url_launcher`**

Edit `pubspec.yaml`. In the `dependencies:` block, after the existing `http:` entry, add:

```yaml
  # EULA first-launch flag (device-local)
  shared_preferences: ^2.2.0

  # Open terms URL in external browser
  url_launcher: ^6.2.0
```

- [ ] **Step 2: Fetch packages and confirm no conflicts**

Run: `flutter pub get`
Expected: "Got dependencies!" with no version-solver errors.

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore(sp2): add shared_preferences and url_launcher"
```

---

### Task 2: Supabase migration — `user_agreements`

**Files:**
- Create: `supabase/migrations/004_user_agreements.sql`

- [ ] **Step 1: Create migrations directory and file**

Create `supabase/migrations/004_user_agreements.sql`:

```sql
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
```

- [ ] **Step 2: Commit**

```bash
git add supabase/migrations/004_user_agreements.sql
git commit -m "feat(sp2): migration 004 user_agreements table"
```

---

### Task 3: Supabase migration — `pin_reports`

**Files:**
- Create: `supabase/migrations/005_pin_reports.sql`

- [ ] **Step 1: Create the migration file**

Create `supabase/migrations/005_pin_reports.sql`:

```sql
-- 005_pin_reports.sql
-- Receives user-submitted reports on pins. No SELECT policy is defined —
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
-- Deliberately no SELECT/UPDATE/DELETE policies — service role only.
```

- [ ] **Step 2: Commit**

```bash
git add supabase/migrations/005_pin_reports.sql
git commit -m "feat(sp2): migration 005 pin_reports table"
```

---

### Task 4: Supabase migration — `blocked_users`

**Files:**
- Create: `supabase/migrations/006_blocked_users.sql`

- [ ] **Step 1: Create the migration file**

Create `supabase/migrations/006_blocked_users.sql`:

```sql
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
```

- [ ] **Step 2: Commit**

```bash
git add supabase/migrations/006_blocked_users.sql
git commit -m "feat(sp2): migration 006 blocked_users table"
```

---

### Task 5: Supabase migration — `pins.name` length

**Files:**
- Create: `supabase/migrations/007_pin_name_length.sql`

- [ ] **Step 1: Confirm the current `pins.name` column does not already have the constraint**

Use Supabase MCP (`mcp__supabase__execute_sql`) or Studio SQL editor to run:

```sql
SELECT conname, pg_get_constraintdef(c.oid)
  FROM pg_constraint c
  JOIN pg_class t ON t.oid = c.conrelid
 WHERE t.relname = 'pins' AND c.contype = 'c';
```

Expected: no constraint mentioning `char_length(name)`. If one is already present with a different expression, coordinate with the user before proceeding.

- [ ] **Step 2: Audit current data**

Run:

```sql
SELECT COUNT(*) AS long_names FROM pins WHERE char_length(name) > 60;
```

If non-zero, stop and surface to the user — those rows will break the migration when the constraint validates. Decision (not in this plan): truncate in place, soft-reject on insert only, or run a backfill. Resume once the user confirms.

- [ ] **Step 3: Create the migration file**

Create `supabase/migrations/007_pin_name_length.sql`:

```sql
-- 007_pin_name_length.sql
-- Cap the pin name at 60 characters. The client also enforces this via
-- TextField(maxLength: 60), but we want the server to reject longer names
-- defensively so manual API callers can't inject long content.
-- Runs only if no row currently violates the constraint — Step 2 of the
-- plan verifies this before the migration is applied.

ALTER TABLE pins
  ADD CONSTRAINT pins_name_length_check
  CHECK (char_length(name) <= 60);
```

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/007_pin_name_length.sql
git commit -m "feat(sp2): migration 007 pin name length <= 60"
```

---

### Task 6: Apply migrations 004–007 to the live Supabase project

**Files:** (none — live database operation)

- [ ] **Step 1: Apply each migration in order via Supabase MCP**

For each file in order (`004`, `005`, `006`, `007`), call `mcp__supabase__apply_migration` with:
- `name`: e.g. `004_user_agreements`
- `query`: contents of the `.sql` file

If the MCP tool is not available, use Supabase Studio → SQL Editor and run each file's contents as a single statement batch.

- [ ] **Step 2: Verify all four tables and the constraint exist**

Run via `mcp__supabase__execute_sql`:

```sql
SELECT table_name
  FROM information_schema.tables
 WHERE table_schema = 'public'
   AND table_name IN ('user_agreements', 'pin_reports', 'blocked_users');

SELECT conname
  FROM pg_constraint
 WHERE conname = 'pins_name_length_check';
```

Expected: all three table names returned + `pins_name_length_check` row returned.

- [ ] **Step 3: No commit**

This task modifies server state, not the repo. Progress marker only.

---

### Task 7: `ProfanityFilter` (TDD)

**Files:**
- Create: `test/core/profanity_filter_test.dart`
- Create: `lib/core/profanity_filter.dart`

- [ ] **Step 1: Write the failing test**

Create `test/core/profanity_filter_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ccwmap/core/profanity_filter.dart';

void main() {
  group('ProfanityFilter.contains', () {
    test('returns false for empty string', () {
      expect(ProfanityFilter.contains(''), isFalse);
    });

    test('returns false for clean text', () {
      expect(ProfanityFilter.contains('Main Street Diner'), isFalse);
      expect(ProfanityFilter.contains('City Hall'), isFalse);
    });

    test('is case-insensitive', () {
      // "FUCK" is in the deny-list; mix case should match.
      expect(ProfanityFilter.contains('This is FUcK'), isTrue);
      expect(ProfanityFilter.contains('this is fuck'), isTrue);
    });

    test('matches substrings (intentional)', () {
      // By design we accept false positives like "Scunthorpe". The report
      // mechanism is the real defense; this filter exists to block the
      // most obvious cases. Verify the intended substring behavior.
      expect(ProfanityFilter.contains('fuckity'), isTrue);
    });

    test('returns false for whitespace-only input', () {
      expect(ProfanityFilter.contains('   '), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `flutter test test/core/profanity_filter_test.dart`
Expected: FAIL — `ProfanityFilter` not defined.

- [ ] **Step 3: Implement `ProfanityFilter`**

Create `lib/core/profanity_filter.dart`:

```dart
/// Minimal client-side profanity check for user-supplied pin names.
///
/// Intentionally minimal — the ~30-word deny-list handles the obvious
/// cases only. Bypasses with leet-speak, spacing, or homoglyphs are
/// tolerated; the report mechanism (see ReportPinDialog) is the real
/// defense against abuse. Per spec: "Obviously bypassable; the report
/// mechanism is the real defense."
class ProfanityFilter {
  // Non-exhaustive by design. Additions should be obvious slurs /
  // profanities that no legitimate place-name would contain.
  static const List<String> _deny = [
    'fuck', 'shit', 'bitch', 'asshole', 'bastard', 'cunt', 'dick',
    'faggot', 'nigger', 'nigga', 'retard', 'retarded', 'slut', 'whore',
    'chink', 'gook', 'kike', 'spic', 'tranny', 'wetback',
    // Add more common slurs here; keep this list short and obvious.
  ];

  /// Returns true if [input] contains any deny-listed substring
  /// (case-insensitive). Whitespace-only and empty inputs return false.
  static bool contains(String input) {
    if (input.trim().isEmpty) return false;
    final lower = input.toLowerCase();
    for (final w in _deny) {
      if (lower.contains(w)) return true;
    }
    return false;
  }
}
```

- [ ] **Step 4: Run the tests and verify they pass**

Run: `flutter test test/core/profanity_filter_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/profanity_filter.dart test/core/profanity_filter_test.dart
git commit -m "feat(sp2): minimal ProfanityFilter for pin names"
```

---

### Task 8: Enforce name constraints in `PinDialog`

**Files:**
- Modify: `lib/presentation/widgets/pin_dialog.dart`

- [ ] **Step 1: Lower the `maxLength` from 100 to 60 and add profanity rejection**

Edit `lib/presentation/widgets/pin_dialog.dart`. Add this import at the top with the others:

```dart
import 'package:ccwmap/core/profanity_filter.dart';
```

Update the `_isValid` getter. Find:

```dart
  bool get _isValid {
    // Name must not be empty
    if (_nameController.text.trim().isEmpty) {
      return false;
    }
    // If NO_GUN status, must have a restriction tag
    if (_selectedStatus == PinStatus.NO_GUN) {
      return _selectedRestrictionTag != null;
    }
    return true;
  }
```

Replace with:

```dart
  bool get _isValid {
    final trimmed = _nameController.text.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.length > 60) return false;
    if (ProfanityFilter.contains(trimmed)) return false;
    if (_selectedStatus == PinStatus.NO_GUN) {
      return _selectedRestrictionTag != null;
    }
    return true;
  }

  /// Message shown below the text field when the current value is not
  /// valid. Returns null when the value is valid (no message needed).
  String? get _nameError {
    final trimmed = _nameController.text.trim();
    if (trimmed.length > 60) {
      return 'Please keep names under 60 characters.';
    }
    if (trimmed.isNotEmpty && ProfanityFilter.contains(trimmed)) {
      return 'Please choose a different name.';
    }
    return null;
  }
```

Update the TextField to reflect the new cap and surface the error. Find:

```dart
              TextField(
                controller: _nameController,
                enabled: !widget.isReadOnly,
                decoration: InputDecoration(
                  hintText: 'Enter a name for this location',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                style: const TextStyle(fontSize: 16),
                maxLength: 100,
                onChanged: (_) => setState(() {}), // Update validation state
              ),
```

Replace with:

```dart
              TextField(
                controller: _nameController,
                enabled: !widget.isReadOnly,
                decoration: InputDecoration(
                  hintText: 'Enter a name for this location',
                  errorText: _nameError,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                style: const TextStyle(fontSize: 16),
                maxLength: 60,
                onChanged: (_) => setState(() {}), // Update validation state
              ),
```

- [ ] **Step 2: Run all existing PinDialog tests**

Run: `flutter test test/presentation/widgets/pin_dialog_readonly_test.dart`
Expected: PASS (tests from SP-1 still pass).

Run: `flutter test`
Expected: no regressions. If any test supplied a name > 60 chars and relied on submit succeeding, fix the test to use a shorter name.

- [ ] **Step 3: Commit**

```bash
git add lib/presentation/widgets/pin_dialog.dart
git commit -m "feat(sp2): cap pin name at 60 chars + profanity reject"
```

---

### Task 9: Repository interfaces — Agreements + Moderation

**Files:**
- Create: `lib/domain/repositories/agreements_repository.dart`
- Create: `lib/domain/repositories/moderation_repository.dart`

- [ ] **Step 1: Create `AgreementsRepository`**

Create `lib/domain/repositories/agreements_repository.dart`:

```dart
/// Tracks whether a given authenticated user has accepted the current
/// version of the EULA / community guidelines.
///
/// Version numbers are monotonic integers. Bump the constant when
/// material wording changes and existing users should be re-prompted.
abstract class AgreementsRepository {
  static const int currentAgreementVersion = 1;

  /// Returns true if [userId] has an accepted row for [version].
  Future<bool> hasAcceptedAgreement({
    required String userId,
    required int version,
  });

  /// Persists acceptance of [version] for [userId].
  Future<void> recordAgreementAcceptance({
    required String userId,
    required int version,
  });
}
```

- [ ] **Step 2: Create `ModerationRepository`**

Create `lib/domain/repositories/moderation_repository.dart`:

```dart
/// Reason codes accepted by the server-side CHECK on `pin_reports.reason`.
/// Keep in sync with migration 005_pin_reports.sql.
enum ReportReason { INACCURATE, OFFENSIVE, SPAM, OTHER }

/// Report-and-block operations for user-generated content moderation.
abstract class ModerationRepository {
  /// Files a report against [pinId]. [note] is optional and capped at
  /// 500 characters server-side. Throws on network/server failure.
  Future<void> submitPinReport({
    required String pinId,
    required ReportReason reason,
    String? note,
  });

  /// Returns the set of user IDs the current user has blocked.
  Future<Set<String>> fetchBlocklist();

  /// Blocks [userId] for the current user. Idempotent; succeeds even if
  /// already blocked.
  Future<void> blockUser(String userId);

  /// Removes [userId] from the current user's blocklist. Idempotent.
  Future<void> unblockUser(String userId);
}
```

- [ ] **Step 3: Commit**

```bash
git add lib/domain/repositories/agreements_repository.dart \
        lib/domain/repositories/moderation_repository.dart
git commit -m "feat(sp2): add AgreementsRepository and ModerationRepository interfaces"
```

---

### Task 10: Data source methods + repository implementations

**Files:**
- Modify: `lib/data/datasources/supabase_remote_data_source.dart`
- Create: `lib/data/repositories/supabase_agreements_repository.dart`
- Create: `lib/data/repositories/supabase_moderation_repository.dart`

**Note on shape:** The existing `RemoteDataSourceInterface` is scoped to pin CRUD for sync. To avoid mixing concerns, the six new methods go directly on `SupabaseRemoteDataSource` *without* adding them to `RemoteDataSourceInterface`, and the new repositories depend on the concrete class (simple construction via DI). If the team later wants to fake these at a lower layer than the repositories, add narrower interfaces at that point.

- [ ] **Step 1: Add six methods to `SupabaseRemoteDataSource`**

Edit `lib/data/datasources/supabase_remote_data_source.dart`. Append these methods inside the class (before the closing brace):

```dart
  // --- SP-2: Agreements ---

  /// Returns true if [userId] has a row in user_agreements for [version].
  Future<bool> hasAcceptedAgreement({
    required String userId,
    required int version,
  }) async {
    final row = await _supabase
        .from('user_agreements')
        .select('id')
        .eq('user_id', userId)
        .eq('agreement_version', version)
        .maybeSingle();
    return row != null;
  }

  /// Records acceptance of [version] for [userId]. Relies on the
  /// UNIQUE (user_id, agreement_version) constraint to make repeated
  /// calls idempotent — a duplicate insert raises a unique-violation
  /// which we swallow.
  Future<void> recordAgreementAcceptance({
    required String userId,
    required int version,
  }) async {
    try {
      await _supabase.from('user_agreements').insert({
        'user_id': userId,
        'agreement_version': version,
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') return; // unique_violation = already accepted
      rethrow;
    }
  }

  // --- SP-2: Moderation ---

  /// Returns the set of user IDs the current user has blocked.
  Future<Set<String>> fetchBlocklist() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return const <String>{};
    final rows = await _supabase
        .from('blocked_users')
        .select('blocked_id')
        .eq('blocker_id', uid);
    return (rows as List)
        .map<String>((r) => (r as Map<String, dynamic>)['blocked_id'] as String)
        .toSet();
  }

  /// Inserts a block row. Idempotent — a duplicate insert (already blocked)
  /// raises unique-violation which we swallow.
  Future<void> blockUser(String blockedUserId) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) {
      throw StateError('blockUser requires authentication');
    }
    try {
      await _supabase.from('blocked_users').insert({
        'blocker_id': uid,
        'blocked_id': blockedUserId,
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') return;
      rethrow;
    }
  }

  /// Removes a block. Idempotent — deleting a non-existent row is a no-op.
  Future<void> unblockUser(String blockedUserId) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) {
      throw StateError('unblockUser requires authentication');
    }
    await _supabase
        .from('blocked_users')
        .delete()
        .eq('blocker_id', uid)
        .eq('blocked_id', blockedUserId);
  }

  /// Files a report. [note] is trimmed; empty notes become null.
  Future<void> submitPinReport({
    required String pinId,
    required String reason,
    String? note,
  }) async {
    final uid = _supabase.auth.currentUser?.id;
    final n = (note == null || note.trim().isEmpty) ? null : note.trim();
    await _supabase.from('pin_reports').insert({
      'pin_id': pinId,
      'reporter_id': uid,
      'reason': reason,
      'note': n,
    });
  }
```

- [ ] **Step 2: Implement `SupabaseAgreementsRepository`**

Create `lib/data/repositories/supabase_agreements_repository.dart`:

```dart
import 'package:ccwmap/data/datasources/supabase_remote_data_source.dart';
import 'package:ccwmap/domain/repositories/agreements_repository.dart';

class SupabaseAgreementsRepository implements AgreementsRepository {
  final SupabaseRemoteDataSource _remote;
  SupabaseAgreementsRepository(this._remote);

  @override
  Future<bool> hasAcceptedAgreement({
    required String userId,
    required int version,
  }) {
    return _remote.hasAcceptedAgreement(userId: userId, version: version);
  }

  @override
  Future<void> recordAgreementAcceptance({
    required String userId,
    required int version,
  }) {
    return _remote.recordAgreementAcceptance(userId: userId, version: version);
  }
}
```

- [ ] **Step 3: Implement `SupabaseModerationRepository`**

Create `lib/data/repositories/supabase_moderation_repository.dart`:

```dart
import 'package:ccwmap/data/datasources/supabase_remote_data_source.dart';
import 'package:ccwmap/domain/repositories/moderation_repository.dart';

class SupabaseModerationRepository implements ModerationRepository {
  final SupabaseRemoteDataSource _remote;
  SupabaseModerationRepository(this._remote);

  @override
  Future<void> submitPinReport({
    required String pinId,
    required ReportReason reason,
    String? note,
  }) {
    return _remote.submitPinReport(
      pinId: pinId,
      reason: reason.name,
      note: note,
    );
  }

  @override
  Future<Set<String>> fetchBlocklist() => _remote.fetchBlocklist();

  @override
  Future<void> blockUser(String userId) => _remote.blockUser(userId);

  @override
  Future<void> unblockUser(String userId) => _remote.unblockUser(userId);
}
```

- [ ] **Step 4: Run `flutter analyze`**

Expected: no errors. `PostgrestException` is re-exported by `supabase_flutter`; no new import should be required (the file already imports `package:supabase_flutter/supabase_flutter.dart`).

- [ ] **Step 5: Commit**

```bash
git add lib/data/datasources/supabase_remote_data_source.dart \
        lib/data/repositories/supabase_agreements_repository.dart \
        lib/data/repositories/supabase_moderation_repository.dart
git commit -m "feat(sp2): data source + repositories for agreements and moderation"
```

---

### Task 11: `BlocklistService` (TDD)

**Files:**
- Create: `test/fakes/fake_moderation_repository.dart`
- Create: `test/data/services/blocklist_service_test.dart`
- Create: `lib/data/services/blocklist_service.dart`

- [ ] **Step 1: Create the fake repository**

Create `test/fakes/fake_moderation_repository.dart`:

```dart
import 'package:ccwmap/domain/repositories/moderation_repository.dart';

class FakeModerationRepository implements ModerationRepository {
  Set<String> remoteBlocklist = <String>{};
  final List<({String pinId, ReportReason reason, String? note})> reports = [];

  @override
  Future<void> submitPinReport({
    required String pinId,
    required ReportReason reason,
    String? note,
  }) async {
    reports.add((pinId: pinId, reason: reason, note: note));
  }

  @override
  Future<Set<String>> fetchBlocklist() async => Set<String>.from(remoteBlocklist);

  @override
  Future<void> blockUser(String userId) async {
    remoteBlocklist.add(userId);
  }

  @override
  Future<void> unblockUser(String userId) async {
    remoteBlocklist.remove(userId);
  }
}
```

- [ ] **Step 2: Write failing tests**

Create `test/data/services/blocklist_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ccwmap/data/services/blocklist_service.dart';
import '../../fakes/fake_moderation_repository.dart';

void main() {
  group('BlocklistService', () {
    late FakeModerationRepository fakeRepo;
    late BlocklistService service;

    setUp(() {
      fakeRepo = FakeModerationRepository();
      service = BlocklistService(fakeRepo);
    });

    test('starts empty', () {
      expect(service.blocked, isEmpty);
      expect(service.isBlocked('abc'), isFalse);
    });

    test('refresh loads remote blocklist', () async {
      fakeRepo.remoteBlocklist = {'user-1', 'user-2'};
      await service.refresh();
      expect(service.blocked, equals({'user-1', 'user-2'}));
      expect(service.isBlocked('user-1'), isTrue);
    });

    test('block updates remote + cache + notifies', () async {
      var notifyCount = 0;
      service.addListener(() => notifyCount++);

      await service.block('target-user');

      expect(fakeRepo.remoteBlocklist, contains('target-user'));
      expect(service.isBlocked('target-user'), isTrue);
      expect(notifyCount, greaterThanOrEqualTo(1));
    });

    test('unblock updates remote + cache + notifies', () async {
      fakeRepo.remoteBlocklist = {'u1'};
      await service.refresh();
      expect(service.isBlocked('u1'), isTrue);

      var notifyCount = 0;
      service.addListener(() => notifyCount++);

      await service.unblock('u1');

      expect(fakeRepo.remoteBlocklist, isNot(contains('u1')));
      expect(service.isBlocked('u1'), isFalse);
      expect(notifyCount, greaterThanOrEqualTo(1));
    });

    test('clear empties the cache without touching remote', () async {
      fakeRepo.remoteBlocklist = {'u1'};
      await service.refresh();
      expect(service.isBlocked('u1'), isTrue);

      service.clear();
      expect(service.blocked, isEmpty);
      expect(fakeRepo.remoteBlocklist, equals({'u1'})); // unchanged
    });
  });
}
```

- [ ] **Step 3: Run tests and verify they fail**

Run: `flutter test test/data/services/blocklist_service_test.dart`
Expected: FAIL — `BlocklistService` undefined.

- [ ] **Step 4: Implement `BlocklistService`**

Create `lib/data/services/blocklist_service.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:ccwmap/domain/repositories/moderation_repository.dart';

/// In-memory cache of the current user's blocklist.
///
/// Design per spec (SP-2): pure in-memory, refreshed on sign-in and after
/// any block/unblock. No Drift persistence in v1. The "offline-before-
/// first-sign-in" gap is acceptable because a guest cannot block anyone
/// — blocking is auth-gated.
///
/// Extends [ChangeNotifier] so [MapViewModel] can refresh its pin stream
/// when the blocklist changes (after calling [block] / [unblock] /
/// [refresh] / [clear]).
class BlocklistService extends ChangeNotifier {
  final ModerationRepository _repo;
  final Set<String> _blocked = <String>{};

  BlocklistService(this._repo);

  /// Unmodifiable view of currently blocked user IDs.
  Set<String> get blocked => Set<String>.unmodifiable(_blocked);

  bool isBlocked(String? userId) => userId != null && _blocked.contains(userId);

  /// Loads the blocklist from the server into the cache. Overwrites any
  /// prior cached state. Call after sign-in.
  Future<void> refresh() async {
    final remote = await _repo.fetchBlocklist();
    _blocked
      ..clear()
      ..addAll(remote);
    notifyListeners();
  }

  Future<void> block(String userId) async {
    await _repo.blockUser(userId);
    _blocked.add(userId);
    notifyListeners();
  }

  Future<void> unblock(String userId) async {
    await _repo.unblockUser(userId);
    _blocked.remove(userId);
    notifyListeners();
  }

  /// Empties the cache. Call on sign-out.
  void clear() {
    if (_blocked.isEmpty) return;
    _blocked.clear();
    notifyListeners();
  }
}
```

- [ ] **Step 5: Run the tests and verify they pass**

Run: `flutter test test/data/services/blocklist_service_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 6: Commit**

```bash
git add test/fakes/fake_moderation_repository.dart \
        test/data/services/blocklist_service_test.dart \
        lib/data/services/blocklist_service.dart
git commit -m "feat(sp2): BlocklistService — in-memory blocklist cache"
```

---

### Task 12: Thread `BlocklistService` into `MapViewModel`

**Files:**
- Modify: `lib/presentation/viewmodels/map_viewmodel.dart`

- [ ] **Step 1: Inject `BlocklistService` and filter the pin stream**

Edit `lib/presentation/viewmodels/map_viewmodel.dart`.

Add an import:

```dart
import '../../data/services/blocklist_service.dart';
```

Update the class to accept and react to a `BlocklistService`. Replace:

```dart
class MapViewModel extends ChangeNotifier {
  final PinRepository _repository;
  final NetworkMonitor _networkMonitor;
  StreamSubscription<List<Pin>>? _pinsSubscription;
  StreamSubscription<bool>? _networkSubscription;

  List<Pin> _pins = [];
  bool _isLoading = false;
  String? _error;
  bool _isSyncing = false;
  DateTime? _lastSyncTime;
  bool _wasOffline = false;

  MapViewModel(this._repository, this._networkMonitor);
```

With:

```dart
class MapViewModel extends ChangeNotifier {
  final PinRepository _repository;
  final NetworkMonitor _networkMonitor;
  final BlocklistService _blocklist;
  StreamSubscription<List<Pin>>? _pinsSubscription;
  StreamSubscription<bool>? _networkSubscription;

  List<Pin> _pinsAll = [];
  List<Pin> _pins = [];
  bool _isLoading = false;
  String? _error;
  bool _isSyncing = false;
  DateTime? _lastSyncTime;
  bool _wasOffline = false;

  MapViewModel(this._repository, this._networkMonitor, this._blocklist) {
    // Re-apply the filter whenever the blocklist changes so the map
    // updates immediately when the user blocks/unblocks someone.
    _blocklist.addListener(_applyBlocklistFilter);
  }
```

Find the pin stream handler:

```dart
      _pinsSubscription = _repository.watchPins().listen(
        (pins) {
          _pins = pins;
          notifyListeners();
        },
```

Replace with:

```dart
      _pinsSubscription = _repository.watchPins().listen(
        (pins) {
          _pinsAll = pins;
          _applyBlocklistFilter();
        },
```

Add two private methods inside the class (above `dispose`):

```dart
  void _applyBlocklistFilter() {
    _pins = _pinsAll
        .where((p) => !_blocklist.isBlocked(p.metadata.createdBy))
        .toList(growable: false);
    notifyListeners();
  }
```

Update `dispose` to detach the blocklist listener. Replace:

```dart
  @override
  void dispose() {
    _pinsSubscription?.cancel();
    _networkSubscription?.cancel();
    super.dispose();
  }
```

With:

```dart
  @override
  void dispose() {
    _blocklist.removeListener(_applyBlocklistFilter);
    _pinsSubscription?.cancel();
    _networkSubscription?.cancel();
    super.dispose();
  }
```

- [ ] **Step 2: Update `main.dart` construction**

Edit `lib/main.dart`. Imports already have `NetworkMonitor`; add:

```dart
import 'package:ccwmap/data/repositories/supabase_agreements_repository.dart';
import 'package:ccwmap/data/repositories/supabase_moderation_repository.dart';
import 'package:ccwmap/data/services/blocklist_service.dart';
```

In `main()`, after `final remoteDataSource = SupabaseRemoteDataSource(supabaseClient);`, add:

```dart
  final moderationRepository = SupabaseModerationRepository(remoteDataSource);
  final agreementsRepository = SupabaseAgreementsRepository(remoteDataSource);
  final blocklistService = BlocklistService(moderationRepository);
```

Update the `MapViewModel` construction. Replace:

```dart
  final mapViewModel = MapViewModel(pinRepository, networkMonitor);
```

With:

```dart
  final mapViewModel = MapViewModel(pinRepository, networkMonitor, blocklistService);
```

Add the new services and repositories to the provider tree. Update `CCWMapApp` to accept them. Replace the `CCWMapApp` class with:

```dart
class CCWMapApp extends StatelessWidget {
  final MapViewModel mapViewModel;
  final AuthViewModel authViewModel;
  final BlocklistService blocklistService;
  final AgreementsRepository agreementsRepository;
  final ModerationRepository moderationRepository;

  const CCWMapApp({
    super.key,
    required this.mapViewModel,
    required this.authViewModel,
    required this.blocklistService,
    required this.agreementsRepository,
    required this.moderationRepository,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: mapViewModel),
        ChangeNotifierProvider.value(value: authViewModel),
        ChangeNotifierProvider.value(value: blocklistService),
        Provider<AgreementsRepository>.value(value: agreementsRepository),
        Provider<ModerationRepository>.value(value: moderationRepository),
      ],
      child: MaterialApp(
        title: 'CCW Map',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6200EE),
            brightness: Brightness.light,
          ),
          appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
        ),
        home: const _AppRoot(),
      ),
    );
  }
}
```

Add matching imports at the top of `main.dart`:

```dart
import 'package:ccwmap/domain/repositories/agreements_repository.dart';
import 'package:ccwmap/domain/repositories/moderation_repository.dart';
```

Update the `runApp` call at the end of `main()`:

```dart
  runApp(CCWMapApp(
    mapViewModel: mapViewModel,
    authViewModel: authViewModel,
    blocklistService: blocklistService,
    agreementsRepository: agreementsRepository,
    moderationRepository: moderationRepository,
  ));
```

- [ ] **Step 3: Create the fake agreements repository**

Create `test/fakes/fake_agreements_repository.dart`:

```dart
import 'package:ccwmap/domain/repositories/agreements_repository.dart';

class FakeAgreementsRepository implements AgreementsRepository {
  final Set<({String userId, int version})> accepted = {};
  bool willReportAccepted = false;

  @override
  Future<bool> hasAcceptedAgreement({
    required String userId,
    required int version,
  }) async {
    if (willReportAccepted) return true;
    return accepted.contains((userId: userId, version: version));
  }

  @override
  Future<void> recordAgreementAcceptance({
    required String userId,
    required int version,
  }) async {
    accepted.add((userId: userId, version: version));
  }
}
```

- [ ] **Step 4: Update `test/widget_test.dart` to build the new `CCWMapApp`**

Edit `test/widget_test.dart`. Add imports near the existing ones:

```dart
import 'package:ccwmap/data/services/blocklist_service.dart';
import 'fakes/fake_moderation_repository.dart';
import 'fakes/fake_agreements_repository.dart';
```

Replace each `MapViewModel(...)` and `CCWMapApp(...)` construction in both tests with:

```dart
      final moderationRepo = FakeModerationRepository();
      final agreementsRepo = FakeAgreementsRepository()
        ..willReportAccepted = true; // skip retroactive EULA modal in tests
      final blocklist = BlocklistService(moderationRepo);

      final mapViewModel = MapViewModel(
        pinRepository,
        fakeNetworkMonitor,
        blocklist,
      );
      final authViewModel = AuthViewModel(authRepository);

      // ...existing setCurrentUser calls...

      await tester.pumpWidget(
        CCWMapApp(
          mapViewModel: mapViewModel,
          authViewModel: authViewModel,
          blocklistService: blocklist,
          agreementsRepository: agreementsRepo,
          moderationRepository: moderationRepo,
        ),
      );
```

- [ ] **Step 5: Run `flutter analyze` + full test suite**

Run: `flutter analyze`
Expected: no new errors.

Run: `flutter test`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/presentation/viewmodels/map_viewmodel.dart \
        lib/main.dart \
        test/widget_test.dart \
        test/fakes/fake_agreements_repository.dart \
        test/fakes/fake_moderation_repository.dart
git commit -m "feat(sp2): wire BlocklistService into MapViewModel and DI"
```

Note: `fake_moderation_repository.dart` was created in Task 11 and already committed there, so git will only stage it if it wasn't picked up previously — the `git add` is idempotent.

---

### Task 13: `EulaModal` widget (TDD)

**Files:**
- Create: `test/presentation/widgets/eula_modal_test.dart`
- Create: `lib/presentation/widgets/eula_modal.dart`

- [ ] **Step 1: Write failing tests**

Create `test/presentation/widgets/eula_modal_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccwmap/presentation/widgets/eula_modal.dart';

void main() {
  group('EulaModal', () {
    testWidgets('passive mode shows Got it + Read full terms; dismissible',
        (tester) async {
      var accepted = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EulaModal(
              mode: EulaModalMode.passiveFirstLaunch,
              onAccept: () => accepted = true,
              onReadTerms: () {},
            ),
          ),
        ),
      );

      expect(find.widgetWithText(ElevatedButton, 'Got it'), findsOneWidget);
      expect(
        find.widgetWithText(TextButton, 'Read full terms'),
        findsOneWidget,
      );
      expect(find.widgetWithText(OutlinedButton, 'Sign Out'), findsNothing);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Got it'));
      await tester.pumpAndSettle();
      expect(accepted, isTrue);
    });

    testWidgets(
        'retroactive mode shows I Agree + Sign Out; no passive Got it',
        (tester) async {
      var agreed = false;
      var signedOut = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EulaModal(
              mode: EulaModalMode.retroactiveBlocking,
              onAccept: () => agreed = true,
              onReadTerms: () {},
              onSignOut: () => signedOut = true,
            ),
          ),
        ),
      );

      expect(find.widgetWithText(ElevatedButton, 'I Agree'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Sign Out'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Got it'), findsNothing);

      await tester.tap(find.widgetWithText(ElevatedButton, 'I Agree'));
      await tester.pumpAndSettle();
      expect(agreed, isTrue);
      expect(signedOut, isFalse);
    });

    testWidgets('Read full terms fires the callback', (tester) async {
      var read = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EulaModal(
              mode: EulaModalMode.passiveFirstLaunch,
              onAccept: () {},
              onReadTerms: () => read = true,
            ),
          ),
        ),
      );

      await tester.tap(find.widgetWithText(TextButton, 'Read full terms'));
      await tester.pumpAndSettle();
      expect(read, isTrue);
    });

    testWidgets('retroactive mode asserts onSignOut is provided',
        (tester) async {
      expect(
        () => EulaModal(
          mode: EulaModalMode.retroactiveBlocking,
          onAccept: () {},
          onReadTerms: () {},
        ),
        throwsAssertionError,
      );
    });
  });
}
```

- [ ] **Step 2: Run tests and confirm failure**

Run: `flutter test test/presentation/widgets/eula_modal_test.dart`
Expected: FAIL — `EulaModal` undefined.

- [ ] **Step 3: Implement `EulaModal`**

Create `lib/presentation/widgets/eula_modal.dart`:

```dart
import 'package:flutter/material.dart';

enum EulaModalMode { passiveFirstLaunch, retroactiveBlocking }

/// Surfaces the Terms of Use and Community Guidelines acceptance UX.
///
/// - [EulaModalMode.passiveFirstLaunch]: shown once per install to
///   everyone (guest or authenticated). Dismissible. "Got it" calls
///   [onAccept]; "Read full terms" calls [onReadTerms].
/// - [EulaModalMode.retroactiveBlocking]: shown on app-start to
///   already-authenticated users who have never accepted the current
///   version. Non-dismissible: the only exits are "I Agree" (calls
///   [onAccept]) and "Sign Out" (calls [onSignOut]).
class EulaModal extends StatelessWidget {
  final EulaModalMode mode;
  final VoidCallback onAccept;
  final VoidCallback onReadTerms;
  final VoidCallback? onSignOut;

  EulaModal({
    super.key,
    required this.mode,
    required this.onAccept,
    required this.onReadTerms,
    this.onSignOut,
  }) : assert(
          mode != EulaModalMode.retroactiveBlocking || onSignOut != null,
          'onSignOut is required for retroactiveBlocking mode',
        );

  @override
  Widget build(BuildContext context) {
    final isRetroactive = mode == EulaModalMode.retroactiveBlocking;

    return AlertDialog(
      title: const Text('Community Guidelines'),
      content: const SingleChildScrollView(
        child: Text(
          'By using CCW Map, you agree to the Terms of Use and Community '
          'Guidelines. Objectionable content and abusive behavior are not '
          'tolerated and may result in account suspension.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: onReadTerms,
          child: const Text('Read full terms'),
        ),
        if (isRetroactive) ...[
          OutlinedButton(
            onPressed: onSignOut,
            child: const Text('Sign Out'),
          ),
          ElevatedButton(
            onPressed: onAccept,
            child: const Text('I Agree'),
          ),
        ] else
          ElevatedButton(
            onPressed: onAccept,
            child: const Text('Got it'),
          ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run the tests and verify they pass**

Run: `flutter test test/presentation/widgets/eula_modal_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/widgets/eula_modal.dart \
        test/presentation/widgets/eula_modal_test.dart
git commit -m "feat(sp2): EulaModal widget with passive + retroactive modes"
```

---

### Task 14: EULA checkbox on signup form

**Files:**
- Modify: `lib/presentation/screens/login_screen.dart`

- [ ] **Step 1: Add signup-time EULA checkbox + gating**

Edit `lib/presentation/screens/login_screen.dart`. Add these imports near the others:

```dart
import 'package:url_launcher/url_launcher.dart';
import 'package:ccwmap/domain/repositories/agreements_repository.dart';
```

Add a state field for the checkbox near the other private fields in `_LoginScreenState`:

Find:

```dart
  bool _obscurePassword = true;
```

Replace with:

```dart
  bool _obscurePassword = true;
  bool _eulaChecked = false;
```

Update `_handleSignUp` to gate on `_eulaChecked` and record acceptance on success. Replace the existing `_handleSignUp`:

```dart
  Future<void> _handleSignUp() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_eulaChecked) return;

    final authViewModel = context.read<AuthViewModel>();
    final agreements = context.read<AgreementsRepository>();
    authViewModel.clearError();

    await authViewModel.signUp(
      _emailController.text.trim(),
      _passwordController.text,
    );

    if (!mounted) return;

    if (authViewModel.error == null) {
      // Record acceptance before email confirmation completes. The row is
      // keyed by user id so the new user — once confirmed and signed in —
      // will not be re-prompted by the retroactive modal.
      final user = authViewModel.currentUser;
      if (user != null) {
        try {
          await agreements.recordAgreementAcceptance(
            userId: user.id,
            version: AgreementsRepository.currentAgreementVersion,
          );
        } catch (_) {
          // Non-fatal: retroactive modal will catch the unrecorded user.
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account created! Check your email to confirm.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }
```

Add a checkbox between the password field and the error-message block, and a terms-link action. Find:

```dart
                      // Password field
                      TextFormField(
                        controller: _passwordController,
                        // ...
                      ),
                      const SizedBox(height: 24),

                      // Error message
```

Replace `const SizedBox(height: 24),` (immediately after the password TextFormField's closing paren) with:

```dart
                      const SizedBox(height: 16),

                      // EULA acceptance (required for signup). Disabled while
                      // loading so users cannot re-check mid-request.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: _eulaChecked,
                            onChanged: isLoading
                                ? null
                                : (v) => setState(() => _eulaChecked = v ?? false),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Wrap(
                                children: [
                                  const Text(
                                    'I agree to the Terms of Use and Community '
                                    'Guidelines and understand that objectionable '
                                    'content and abusive behavior are not '
                                    'tolerated. ',
                                  ),
                                  TextButton(
                                    onPressed: isLoading
                                        ? null
                                        : _openTermsUrl,
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: const Text('Read terms'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Error message
```

Find the signup button and gate it on `_eulaChecked`. Replace:

```dart
                      // Sign Up button
                      OutlinedButton(
                        onPressed: isLoading ? null : _handleSignUp,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('Create Account'),
                      ),
```

With:

```dart
                      // Sign Up button (disabled until EULA checked)
                      OutlinedButton(
                        onPressed: (isLoading || !_eulaChecked)
                            ? null
                            : _handleSignUp,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('Create Account'),
                      ),
```

Add the `_openTermsUrl` helper near the other private methods in `_LoginScreenState`:

```dart
  Future<void> _openTermsUrl() async {
    final uri = Uri.parse('https://camiloh12.github.io/ccwmap/terms');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
```

- [ ] **Step 2: Run analyze + widget tests**

Run: `flutter analyze`
Expected: no errors.

Run: `flutter test`
Expected: existing tests pass. The two `widget_test.dart` tests don't exercise signup so they are unaffected.

- [ ] **Step 3: Commit**

```bash
git add lib/presentation/screens/login_screen.dart
git commit -m "feat(sp2): EULA checkbox gates signup"
```

---

### Task 15: Wire first-launch + retroactive EULA gates in `_AppRoot`

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: Add imports**

Edit `lib/main.dart`. Add near the other imports:

```dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ccwmap/presentation/widgets/eula_modal.dart';
```

- [ ] **Step 2: Extend `_AppRootState` with EULA state + logic**

Replace the entire `_AppRootState` class body with:

```dart
class _AppRootState extends State<_AppRoot> {
  static const _eulaFlagKey = 'eula_acknowledged_v1';

  StreamSubscription<Uri>? _deepLinkSubscription;
  bool _passiveEulaShown = false;
  bool _retroactiveEulaChecked = false;
  User? _lastAuthUser;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = context.read<AuthViewModel>();
      auth.initialize();
      _initializeDeepLinkListener(auth);
      await _maybeShowPassiveEula();
    });
  }

  Future<void> _initializeDeepLinkListener(AuthViewModel authViewModel) async {
    final appLinks = AppLinks();

    try {
      final initialLink = await appLinks.getInitialLink();
      if (initialLink != null) {
        await authViewModel.handleDeepLink(initialLink);
      }
    } catch (e) {
      authViewModel.setError('Failed to process authentication link.');
    }

    _deepLinkSubscription = appLinks.uriLinkStream.listen(
      (uri) => authViewModel.handleDeepLink(uri),
      onError: (_) =>
          authViewModel.setError('Failed to process authentication link.'),
    );
  }

  Future<void> _maybeShowPassiveEula() async {
    if (_passiveEulaShown) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_eulaFlagKey) == true) {
      _passiveEulaShown = true;
      return;
    }
    _passiveEulaShown = true;

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => EulaModal(
        mode: EulaModalMode.passiveFirstLaunch,
        onAccept: () async {
          await prefs.setBool(_eulaFlagKey, true);
          if (ctx.mounted) Navigator.of(ctx).pop();
        },
        onReadTerms: _openTermsUrl,
      ),
    );
  }

  Future<void> _maybeShowRetroactiveEula(User user) async {
    if (_retroactiveEulaChecked) return;
    _retroactiveEulaChecked = true;

    final agreements = context.read<AgreementsRepository>();
    final blocklist = context.read<BlocklistService>();
    final auth = context.read<AuthViewModel>();

    // Refresh blocklist now that a user is signed in.
    try {
      await blocklist.refresh();
    } catch (_) {/* non-fatal */}

    bool accepted;
    try {
      accepted = await agreements.hasAcceptedAgreement(
        userId: user.id,
        version: AgreementsRepository.currentAgreementVersion,
      );
    } catch (_) {
      return; // don't block on transient errors
    }
    if (accepted) return;

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: EulaModal(
          mode: EulaModalMode.retroactiveBlocking,
          onAccept: () async {
            try {
              await agreements.recordAgreementAcceptance(
                userId: user.id,
                version: AgreementsRepository.currentAgreementVersion,
              );
            } catch (_) {/* non-fatal */}
            if (ctx.mounted) Navigator.of(ctx).pop();
          },
          onReadTerms: _openTermsUrl,
          onSignOut: () async {
            if (ctx.mounted) Navigator.of(ctx).pop();
            await auth.signOut();
          },
        ),
      ),
    );
  }

  Future<void> _openTermsUrl() async {
    final uri = Uri.parse('https://camiloh12.github.io/ccwmap/terms');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  void dispose() {
    _deepLinkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Trigger the retroactive check when an authenticated user becomes
    // available (post-initialize or post-signin). Firing here instead of
    // in initState lets us observe the auth-state change cleanly.
    final auth = context.watch<AuthViewModel>();
    final current = auth.currentUser;
    if (current != null && current != _lastAuthUser) {
      _lastAuthUser = current;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _retroactiveEulaChecked = false; // re-check on each new sign-in
        _maybeShowRetroactiveEula(current);
      });
    }
    if (current == null && _lastAuthUser != null) {
      // User signed out — clear cached blocklist and reset retroactive flag.
      context.read<BlocklistService>().clear();
      _lastAuthUser = null;
      _retroactiveEulaChecked = false;
    }
    return const MapScreen();
  }
}
```

At the top of `main.dart`, add the missing import for `User`:

```dart
import 'package:ccwmap/domain/models/user.dart';
```

- [ ] **Step 3: Run analyze + tests**

Run: `flutter analyze`
Expected: no errors.

Run: `flutter test`
Expected: all pass. If any test fails because `SharedPreferences.getInstance()` was not mocked, add `SharedPreferences.setMockInitialValues({})` in the test `setUp`.

If the existing `test/widget_test.dart` tests fail because of `SharedPreferences`, edit them to include:

```dart
import 'package:shared_preferences/shared_preferences.dart';

setUp(() {
  SharedPreferences.setMockInitialValues({'eula_acknowledged_v1': true});
});
```

just inside each test body (before the `pumpWidget` call) so the passive EULA doesn't block the test from settling.

- [ ] **Step 4: Commit**

```bash
git add lib/main.dart test/widget_test.dart
git commit -m "feat(sp2): passive + retroactive EULA gates in _AppRoot"
```

---

### Task 16: `ReportPinDialog` widget (TDD)

**Files:**
- Create: `test/presentation/widgets/report_pin_dialog_test.dart`
- Create: `lib/presentation/widgets/report_pin_dialog.dart`

- [ ] **Step 1: Write failing tests**

Create `test/presentation/widgets/report_pin_dialog_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccwmap/domain/repositories/moderation_repository.dart';
import 'package:ccwmap/presentation/widgets/report_pin_dialog.dart';

void main() {
  group('ReportPinDialog', () {
    testWidgets('lists four reason radios and Submit/Cancel', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportPinDialog(onSubmit: (_, __) async {}),
          ),
        ),
      );

      expect(find.text('Inaccurate'), findsOneWidget);
      expect(find.text('Offensive'), findsOneWidget);
      expect(find.text('Spam'), findsOneWidget);
      expect(find.text('Other'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Submit'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
    });

    testWidgets('Submit is disabled until a reason is selected',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportPinDialog(onSubmit: (_, __) async {}),
          ),
        ),
      );
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Submit'),
      );
      expect(button.onPressed, isNull);

      await tester.tap(find.text('Offensive'));
      await tester.pumpAndSettle();
      final button2 = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Submit'),
      );
      expect(button2.onPressed, isNotNull);
    });

    testWidgets('Submit invokes callback with selected reason and note',
        (tester) async {
      ReportReason? captured;
      String? capturedNote;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportPinDialog(
              onSubmit: (reason, note) async {
                captured = reason;
                capturedNote = note;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Spam'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'duplicate of another');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Submit'));
      await tester.pumpAndSettle();

      expect(captured, equals(ReportReason.SPAM));
      expect(capturedNote, equals('duplicate of another'));
    });
  });
}
```

- [ ] **Step 2: Run tests and confirm they fail**

Run: `flutter test test/presentation/widgets/report_pin_dialog_test.dart`
Expected: FAIL — `ReportPinDialog` undefined.

- [ ] **Step 3: Implement `ReportPinDialog`**

Create `lib/presentation/widgets/report_pin_dialog.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:ccwmap/domain/repositories/moderation_repository.dart';

typedef ReportSubmitCallback = Future<void> Function(
  ReportReason reason,
  String? note,
);

/// Reason picker + optional free-text note for reporting a pin.
/// Returns via [onSubmit]. The caller is responsible for popping the
/// surrounding dialog and showing the confirmation snackbar.
class ReportPinDialog extends StatefulWidget {
  final ReportSubmitCallback onSubmit;

  const ReportPinDialog({super.key, required this.onSubmit});

  @override
  State<ReportPinDialog> createState() => _ReportPinDialogState();
}

class _ReportPinDialogState extends State<ReportPinDialog> {
  ReportReason? _selected;
  final TextEditingController _noteController = TextEditingController();
  bool _submitting = false;

  static const List<(ReportReason, String)> _options = [
    (ReportReason.INACCURATE, 'Inaccurate'),
    (ReportReason.OFFENSIVE, 'Offensive'),
    (ReportReason.SPAM, 'Spam'),
    (ReportReason.OTHER, 'Other'),
  ];

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    final reason = _selected;
    if (reason == null || _submitting) return;
    setState(() => _submitting = true);
    final note = _noteController.text.trim();
    await widget.onSubmit(reason, note.isEmpty ? null : note);
    if (!mounted) return;
    setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Report this pin'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (r, label) in _options)
              RadioListTile<ReportReason>(
                value: r,
                groupValue: _selected,
                title: Text(label),
                onChanged: _submitting
                    ? null
                    : (v) => setState(() => _selected = v),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteController,
              enabled: !_submitting,
              maxLength: 500,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: (_selected == null || _submitting) ? null : _handleSubmit,
          child: const Text('Submit'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run the tests and verify they pass**

Run: `flutter test test/presentation/widgets/report_pin_dialog_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/widgets/report_pin_dialog.dart \
        test/presentation/widgets/report_pin_dialog_test.dart
git commit -m "feat(sp2): ReportPinDialog reason picker + note"
```

---

### Task 17: Conditional Report/Block buttons in `PinDialog`

**Files:**
- Modify: `lib/presentation/widgets/pin_dialog.dart`
- Create: `test/presentation/widgets/pin_dialog_report_block_test.dart`

- [ ] **Step 1: Extend `PinDialog` with `onReport` and `onBlock` callbacks**

Edit `lib/presentation/widgets/pin_dialog.dart`. Add two optional parameters to the constructor near `onSignInToEdit`:

Find:

```dart
    this.isReadOnly = false,
    this.onSignInToEdit,
  }) : assert(
         !isReadOnly || onSignInToEdit != null,
         'onSignInToEdit is required when isReadOnly is true',
       );
```

Replace with:

```dart
    this.isReadOnly = false,
    this.onSignInToEdit,
    this.onReport,
    this.onBlock,
  }) : assert(
         !isReadOnly || onSignInToEdit != null,
         'onSignInToEdit is required when isReadOnly is true',
       );
```

Add matching fields near `onSignInToEdit`:

Find:

```dart
  final bool isReadOnly;
  final VoidCallback? onSignInToEdit;
```

Replace with:

```dart
  final bool isReadOnly;
  final VoidCallback? onSignInToEdit;
  final VoidCallback? onReport;
  final VoidCallback? onBlock;
```

Show the Report and Block buttons in writable-edit mode only when both callbacks are provided. Find the Delete-button block (edit mode + writable only) and insert the new buttons between the Delete button and the action-buttons Row. Find:

```dart
              // Delete Button (edit mode + writable only)
              if (!widget.isReadOnly &&
                  widget.isEditMode &&
                  widget.onDelete != null) ...[
                OutlinedButton.icon(
                  onPressed: widget.onDelete,
                  // ... Delete Pin label etc ...
                ),
                const SizedBox(height: 16),
              ],

              // Action Buttons
              if (widget.isReadOnly)
```

Replace the inserted comment/section with:

```dart
              // Report / Block (edit mode + writable + callbacks provided).
              // Filtered upstream in MapScreen so these are only wired for
              // other users' pins (not own pins, not anonymous pins).
              if (!widget.isReadOnly &&
                  widget.isEditMode &&
                  (widget.onReport != null || widget.onBlock != null)) ...[
                if (widget.onReport != null)
                  TextButton.icon(
                    onPressed: widget.onReport,
                    icon: const Icon(Icons.flag_outlined),
                    label: const Text('Report pin'),
                  ),
                if (widget.onBlock != null)
                  TextButton.icon(
                    onPressed: widget.onBlock,
                    icon: const Icon(Icons.block),
                    label: const Text('Block creator of this pin'),
                  ),
                const SizedBox(height: 8),
              ],

              // Delete Button (edit mode + writable only)
              if (!widget.isReadOnly &&
                  widget.isEditMode &&
                  widget.onDelete != null) ...[
                OutlinedButton.icon(
                  onPressed: widget.onDelete,
```

(ensuring the rest of the Delete-button block and the Action Buttons block stay exactly as they were).

- [ ] **Step 2: Write widget tests**

Create `test/presentation/widgets/pin_dialog_report_block_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccwmap/domain/models/pin_status.dart';
import 'package:ccwmap/presentation/widgets/pin_dialog.dart';

void main() {
  group('PinDialog Report/Block buttons', () {
    testWidgets('hidden in create mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PinDialog(
              isEditMode: false,
              poiName: 'x',
              initialStatus: PinStatus.ALLOWED,
              onConfirm: (_) {},
              onCancel: () {},
              onReport: () {},
              onBlock: () {},
            ),
          ),
        ),
      );
      expect(find.text('Report pin'), findsNothing);
      expect(find.text('Block creator of this pin'), findsNothing);
    });

    testWidgets('hidden in read-only mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PinDialog(
              isEditMode: true,
              isReadOnly: true,
              poiName: 'x',
              initialStatus: PinStatus.ALLOWED,
              onConfirm: (_) {},
              onCancel: () {},
              onSignInToEdit: () {},
              onReport: () {},
              onBlock: () {},
            ),
          ),
        ),
      );
      expect(find.text('Report pin'), findsNothing);
      expect(find.text('Block creator of this pin'), findsNothing);
    });

    testWidgets('hidden in edit mode when callbacks are null', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PinDialog(
              isEditMode: true,
              poiName: 'x',
              initialStatus: PinStatus.ALLOWED,
              onConfirm: (_) {},
              onCancel: () {},
              onDelete: () {},
            ),
          ),
        ),
      );
      expect(find.text('Report pin'), findsNothing);
      expect(find.text('Block creator of this pin'), findsNothing);
    });

    testWidgets('visible in edit mode when callbacks provided', (tester) async {
      var reported = false;
      var blocked = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PinDialog(
              isEditMode: true,
              poiName: 'x',
              initialStatus: PinStatus.ALLOWED,
              onConfirm: (_) {},
              onCancel: () {},
              onDelete: () {},
              onReport: () => reported = true,
              onBlock: () => blocked = true,
            ),
          ),
        ),
      );

      // Scroll the dialog into view if needed.
      await tester.ensureVisible(find.text('Report pin'));
      await tester.tap(find.text('Report pin'));
      await tester.pumpAndSettle();
      expect(reported, isTrue);

      await tester.ensureVisible(find.text('Block creator of this pin'));
      await tester.tap(find.text('Block creator of this pin'));
      await tester.pumpAndSettle();
      expect(blocked, isTrue);
    });
  });
}
```

- [ ] **Step 3: Run the tests and verify they pass**

Run: `flutter test test/presentation/widgets/pin_dialog_report_block_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 4: Commit**

```bash
git add lib/presentation/widgets/pin_dialog.dart \
        test/presentation/widgets/pin_dialog_report_block_test.dart
git commit -m "feat(sp2): conditional Report/Block buttons in PinDialog"
```

---

### Task 18: Wire Report/Block in `MapScreen`

**Files:**
- Modify: `lib/presentation/screens/map_screen.dart`

- [ ] **Step 1: Import the new surfaces**

Add these imports to `map_screen.dart`:

```dart
import 'package:ccwmap/data/services/blocklist_service.dart';
import 'package:ccwmap/domain/repositories/moderation_repository.dart';
import 'package:ccwmap/presentation/widgets/report_pin_dialog.dart';
```

- [ ] **Step 2: Pass `onReport` and `onBlock` into the writable `PinDialog`**

Find `_showPinDialog`. At the top of its implementation, determine whether the viewer is a non-owner authenticated user of a non-anonymous pin, and capture the pin creator id:

Replace the existing signature and top of `_showPinDialog` — find:

```dart
  Future<void> _showPinDialog({
    required bool isEditMode,
    required String poiName,
    required PinStatus? initialStatus,
    required RestrictionTag? initialRestrictionTag,
    required bool initialHasSecurityScreening,
    required bool initialHasPostedSignage,
    String? pinId, // For edit mode
    LatLng? coordinates, // For create mode
  }) async {
    // Set flag to prevent multiple dialogs
    _isDialogOpen = true;
```

Replace with:

```dart
  Future<void> _showPinDialog({
    required bool isEditMode,
    required String poiName,
    required PinStatus? initialStatus,
    required RestrictionTag? initialRestrictionTag,
    required bool initialHasSecurityScreening,
    required bool initialHasPostedSignage,
    String? pinId, // For edit mode
    LatLng? coordinates, // For create mode
  }) async {
    _isDialogOpen = true;

    // Resolve the creator id up front — needed for Report/Block visibility.
    final auth = Provider.of<AuthViewModel>(context, listen: false);
    final currentUserId = auth.currentUser?.id;
    String? pinCreatorId;
    if (isEditMode && pinId != null) {
      final existing = await _viewModel?.getPinById(pinId);
      pinCreatorId = existing?.metadata.createdBy;
    }
    final canModerate = isEditMode &&
        currentUserId != null &&
        pinCreatorId != null &&
        pinCreatorId != currentUserId;
```

In the `builder:` of the `showDialog` inside `_showPinDialog`, add `onReport`/`onBlock` to the `PinDialog` invocation. Find:

```dart
      builder: (dialogContext) => PinDialog(
        isEditMode: isEditMode,
        poiName: poiName,
        initialStatus: initialStatus,
        initialRestrictionTag: initialRestrictionTag,
        initialHasSecurityScreening: initialHasSecurityScreening,
        initialHasPostedSignage: initialHasPostedSignage,
        onConfirm: (result) async {
```

Replace with:

```dart
      builder: (dialogContext) => PinDialog(
        isEditMode: isEditMode,
        poiName: poiName,
        initialStatus: initialStatus,
        initialRestrictionTag: initialRestrictionTag,
        initialHasSecurityScreening: initialHasSecurityScreening,
        initialHasPostedSignage: initialHasPostedSignage,
        onReport: canModerate && pinId != null
            ? () => _handleReportPin(dialogContext, pinId)
            : null,
        onBlock: canModerate && pinCreatorId != null
            ? () =>
                _handleBlockUser(dialogContext, pinCreatorId!, pinId!)
            : null,
        onConfirm: (result) async {
```

- [ ] **Step 3: Add report/block handlers**

Add these methods on `_MapScreenState` (place them just before `_showReadOnlyPinDialog`):

```dart
  Future<void> _handleReportPin(BuildContext dialogContext, String pinId) async {
    final moderation = Provider.of<ModerationRepository>(context, listen: false);

    final navigator = Navigator.of(dialogContext, rootNavigator: true);
    // Close the PinDialog first so the report sub-dialog is the topmost modal.
    navigator.pop();

    await showDialog<void>(
      context: context,
      builder: (ctx) => ReportPinDialog(
        onSubmit: (reason, note) async {
          try {
            await moderation.submitPinReport(
              pinId: pinId,
              reason: reason,
              note: note,
            );
            if (ctx.mounted) Navigator.of(ctx).pop();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Report submitted. Thanks for helping keep the map accurate.',
                  ),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 3),
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Report failed: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        },
      ),
    );
  }

  Future<void> _handleBlockUser(
    BuildContext dialogContext,
    String userId,
    String pinId,
  ) async {
    final blocklist = Provider.of<BlocklistService>(context, listen: false);

    final confirmed = await showDialog<bool>(
      context: dialogContext,
      builder: (ctx) => AlertDialog(
        title: const Text('Block this user?'),
        content: const Text(
          "You won't see any of their pins anymore.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text(
              'Block',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    Navigator.of(dialogContext, rootNavigator: true).pop();

    try {
      await blocklist.block(userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User blocked.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Block failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
```

- [ ] **Step 4: Run analyze + tests**

Run: `flutter analyze`
Expected: no errors.

Run: `flutter test`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/screens/map_screen.dart
git commit -m "feat(sp2): wire Report/Block flows from PinDialog"
```

---

### Task 19: `send-moderation-email` Edge Function

**Files:**
- Create: `supabase/functions/send-moderation-email/index.ts`
- Create: `supabase/functions/send-moderation-email/deno.json`
- Create: `supabase/.gitignore`

- [ ] **Step 1: Scaffold the function**

Create `supabase/.gitignore`:

```
.env
.env.local
functions/*/.env
functions/*/.env.local
```

Create `supabase/functions/send-moderation-email/deno.json`:

```json
{
  "imports": {
    "std/": "https://deno.land/std@0.224.0/"
  }
}
```

Create `supabase/functions/send-moderation-email/index.ts`:

```typescript
// Supabase Edge Function: send-moderation-email
//
// Triggered by two Supabase Database Webhooks:
//   1. INSERT INTO public.pin_reports
//   2. INSERT INTO public.blocked_users
//
// Webhook payload shape (Supabase "Database Webhook" format):
//   { type: "INSERT", table: string, schema: "public", record: {...}, old_record: null }
//
// The function formats a plain-text email with everything the moderator
// needs to act (reporter/blocker id, pin id, coordinates, reason, note,
// timestamp, a deep link into Supabase Studio) and ships it via Resend.

import "jsr:@std/dotenv/load";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const MOD_FROM = Deno.env.get("MOD_FROM") ?? "moderation@kyberneticlabs.com";
const MOD_TO = Deno.env.get("MOD_TO") ?? "camilo@kyberneticlabs.com";

interface WebhookPayload {
  type: "INSERT" | "UPDATE" | "DELETE";
  table: string;
  schema: string;
  record: Record<string, unknown>;
  old_record: Record<string, unknown> | null;
}

function studioLink(table: string, rowId: string): string {
  const host = SUPABASE_URL.replace(/^https?:\/\//, "").replace(/\.supabase\.co.*$/, "");
  return `https://supabase.com/dashboard/project/${host}/editor?table=${table}&row=${rowId}`;
}

async function sendEmail(subject: string, body: string): Promise<void> {
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${RESEND_API_KEY}`,
    },
    body: JSON.stringify({
      from: MOD_FROM,
      to: [MOD_TO],
      subject,
      text: body,
    }),
  });
  if (!res.ok) {
    const txt = await res.text();
    throw new Error(`Resend error ${res.status}: ${txt}`);
  }
}

function formatReport(r: Record<string, unknown>): { subject: string; body: string } {
  const subject = `[CCW Map] Pin reported — ${r.reason}`;
  const body = [
    `pin_id:     ${r.pin_id}`,
    `reporter:   ${r.reporter_id ?? "anonymous"}`,
    `reason:     ${r.reason}`,
    `note:       ${r.note ?? "(none)"}`,
    `created_at: ${r.created_at}`,
    ``,
    `Studio:     ${studioLink("pin_reports", String(r.id))}`,
    `Pin row:    ${studioLink("pins", String(r.pin_id))}`,
  ].join("\n");
  return { subject, body };
}

function formatBlock(r: Record<string, unknown>): { subject: string; body: string } {
  const subject = `[CCW Map] User blocked`;
  const body = [
    `blocker_id: ${r.blocker_id}`,
    `blocked_id: ${r.blocked_id}`,
    `created_at: ${r.created_at}`,
    ``,
    `Moderator note: repeated blocks on the same blocked_id are a signal`,
    `to review that user's pins manually.`,
  ].join("\n");
  return { subject, body };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }
  let payload: WebhookPayload;
  try {
    payload = await req.json();
  } catch {
    return new Response("Invalid JSON", { status: 400 });
  }

  try {
    let msg: { subject: string; body: string };
    if (payload.table === "pin_reports" && payload.type === "INSERT") {
      msg = formatReport(payload.record);
    } else if (payload.table === "blocked_users" && payload.type === "INSERT") {
      msg = formatBlock(payload.record);
    } else {
      return new Response(`Ignored ${payload.table}/${payload.type}`, {
        status: 200,
      });
    }
    await sendEmail(msg.subject, msg.body);
    return new Response("ok", { status: 200 });
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    return new Response(`error: ${message}`, { status: 500 });
  }
});
```

- [ ] **Step 2: Commit**

```bash
git add supabase/.gitignore \
        supabase/functions/send-moderation-email/index.ts \
        supabase/functions/send-moderation-email/deno.json
git commit -m "feat(sp2): send-moderation-email Edge Function"
```

---

### Task 20: Deploy the Edge Function and wire the webhooks

**Files:** (none — live Supabase operations)

- [ ] **Step 1: Set the Resend secret**

Run (with the Supabase CLI installed locally, or ask the user to run):

```bash
supabase secrets set RESEND_API_KEY=<api-key>
supabase secrets set MOD_FROM=moderation@kyberneticlabs.com
supabase secrets set MOD_TO=camilo@kyberneticlabs.com
```

If the Resend custom-domain is not yet configured, use a Resend sandbox address for `MOD_FROM` (e.g., `onboarding@resend.dev`) and update later.

- [ ] **Step 2: Deploy the function**

Run:

```bash
supabase functions deploy send-moderation-email
```

Expected: "Deployed Functions: send-moderation-email" and a URL of the form `https://<project-ref>.supabase.co/functions/v1/send-moderation-email`. Capture that URL for Step 3.

- [ ] **Step 3: Create two Supabase Database Webhooks (Studio)**

In Supabase Studio → Database → Webhooks → Create a new hook:

**Webhook 1 — pin reports**
- Name: `pin_reports_moderation`
- Table: `pin_reports`
- Events: `INSERT`
- Type: HTTP Request
- Method: `POST`
- URL: the Edge Function URL from Step 2
- HTTP Headers: `Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>`, `Content-Type: application/json`

**Webhook 2 — blocked users**
- Name: `blocked_users_moderation`
- Table: `blocked_users`
- Events: `INSERT`
- Type: HTTP Request
- Method: `POST`
- URL: the Edge Function URL from Step 2
- HTTP Headers: `Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>`, `Content-Type: application/json`

- [ ] **Step 4: Smoke-test**

Insert a test row via Studio SQL editor:

```sql
INSERT INTO pin_reports (pin_id, reporter_id, reason, note)
  SELECT id, auth.uid(), 'INACCURATE', 'webhook smoke test'
    FROM pins LIMIT 1;
```

Expect an email to `camilo@kyberneticlabs.com` within a minute. If nothing arrives, check **Function Logs** in Studio for the invocation and the Resend dashboard for delivery status.

- [ ] **Step 5: No commit** (live operations only).

---

### Task 21: `docs/MODERATION.md`

**Files:**
- Create: `docs/MODERATION.md`

- [ ] **Step 1: Write the operational playbook**

Create `docs/MODERATION.md`:

```markdown
# Moderation Playbook

SLA: **24 hours** from email receipt to pin-action + ban decision.

## Email signals

Two subject-line prefixes drive triage:

| Subject | Signal |
|---|---|
| `[CCW Map] Pin reported — <REASON>` | A user submitted a report via `ReportPinDialog`. |
| `[CCW Map] User blocked` | A user blocked another user. Not a report — but repeated blocks against the same `blocked_id` are a signal to review that user's pins manually. |

## Review rubric

- **OFFENSIVE / SPAM:** delete the pin immediately. If it's the user's first offense AND the content isn't a slur, leave the account alone. Otherwise ban.
- **INACCURATE:** verify against ground truth (MapTiler base map, public signage photos, news). If clearly wrong, delete. If uncertain, mark mentally for follow-up.
- **OTHER + note:** read the note; decide case-by-case.

## Action procedure

1. **Open Supabase Studio → Table Editor → `pins`**; filter by `id = <from email>`; delete the row.
2. **If banning:** Studio → Authentication → Users → search for `<user_id>` → "Ban user" → set duration to "Permanent" (or the `banned_until = 'infinity'` idiom once confirmed by Supabase support).
3. If the pin was referenced by multiple reports, check `pin_reports` for any additional notes before deciding.

## What ban does

- The next auth refresh (up to ~1 hour) will fail with the "banned" auth exception. The app maps that to "This account has been suspended for violating the community guidelines. For appeals, email camilo@kyberneticlabs.com." (SP-3 Task TBD.)
- Ban does **not** delete the user's other pins. The single offending pin is deleted manually in step 1; other pins remain so the map keeps the information. Delete additional pins only if they are similarly violating.

## Absence / backup

Solo project — no backup moderator. Supabase Studio works on mobile, so even travel is not a blocker for 24h SLA. If absence > 24h is expected, pause the moderation webhooks in Studio (this prevents a pile-up; emails still arrive once re-enabled).

## Appeals

Appeal address published in-app and on the GitHub Pages terms page: `camilo@kyberneticlabs.com`. No formal appeal form; decisions are handled by email.
```

- [ ] **Step 2: Commit**

```bash
git add docs/MODERATION.md
git commit -m "docs(sp2): moderation playbook"
```

---

### Task 22: `docs/DEPLOY.md`

**Files:**
- Create: `docs/DEPLOY.md`

- [ ] **Step 1: Write deploy steps**

Create `docs/DEPLOY.md`:

```markdown
# Deploying Supabase Edge Functions

Manual deploy process. Auto-deploy via GitHub Actions is a future enhancement.

## Prerequisites

- Supabase CLI installed: `npm i -g supabase` (or `brew install supabase/tap/supabase`).
- Logged in: `supabase login`.
- Linked: `supabase link --project-ref <project-ref>`.

## First-time setup (secrets)

```bash
supabase secrets set RESEND_API_KEY=<api-key>
supabase secrets set MOD_FROM=moderation@kyberneticlabs.com
supabase secrets set MOD_TO=camilo@kyberneticlabs.com
```

## Deploy a function

```bash
supabase functions deploy send-moderation-email
supabase functions deploy delete-account     # once SP-3 lands
```

Confirm deployment in Studio → Edge Functions. The invocation URL is
`https://<project-ref>.supabase.co/functions/v1/<function-name>`.

## Migrations

Migrations under `supabase/migrations/*.sql` are applied manually in SQL
editor for v0.4.0 (or via `supabase db push` if the project is linked).
Always apply in numeric order. Verify via the table / constraint checks
in the plan for each migration.
```

- [ ] **Step 2: Commit**

```bash
git add docs/DEPLOY.md
git commit -m "docs(sp2): edge function deploy playbook"
```

---

### Task 23: End-to-end manual test on an Android emulator

**Files:** (none — manual)

- [ ] **Step 1: Clear shared_preferences and launch cold**

Either uninstall the app or manually clear app data. Launch the app.
Expected: the passive EULA modal shows. Tap "Read full terms" → external browser opens with `https://camiloh12.github.io/ccwmap/terms`. (If the terms page isn't published yet, browser will show 404 — that's acceptable at this stage, but the page MUST exist before production submission.) Return to the app. Tap "Got it" → modal dismisses.

- [ ] **Step 2: Sign up + EULA checkbox**

Tap the sign-in icon (top-right) → Sign In → Create Account on the LoginScreen. Verify:
- "Create Account" button is disabled until the EULA checkbox is checked.
- Tap "Read terms" → external browser opens.
- Check the box → button enables → submit.
- Email confirmation arrives; follow the deep link back to the app.

- [ ] **Step 3: Report a pin + Block the creator**

Sign in as a second user. Tap any pin created by the first user. Verify:
- `PinDialog` opens in edit mode (writable).
- "Report pin" and "Block creator of this pin" buttons are visible.
- Tap "Report pin" → `ReportPinDialog` opens. Pick "Spam", type a note, submit. Success snackbar appears. Developer receives the email.
- Reopen the same pin. Tap "Block creator of this pin" → confirm. The pin disappears from the map immediately. Developer receives the block email.

- [ ] **Step 4: Retroactive EULA**

In Supabase Studio, delete the current user's row from `user_agreements`. Kill + relaunch the app. Expected: a non-dismissible EULA modal appears. Back button does nothing. Tap "I Agree" → modal dismisses → a new row appears in `user_agreements`. Repeat test with "Sign Out" option → verify it signs the user out and returns to guest state.

- [ ] **Step 5: Name constraints**

Create a pin. Try a 61-char name → error text appears, Create disabled. Try "bullshit emporium" → error "Please choose a different name." Try a valid 59-char name → Create succeeds.

- [ ] **Step 6: No commit**

Manual verification only.

---

### Task 24: Update `CLAUDE.md` status

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update the implementation checklist**

Find the "What's Implemented" block (updated in SP-1 Task 8) and append:

```markdown
- ✅ EULA acceptance (first-launch passive + signup checkbox + retroactive blocking)
- ✅ User report + block flows with server-side tables and moderation-email webhook
- ✅ Pin name constraints (60-char cap + minimal profanity filter)
```

- [ ] **Step 2: Document the new Supabase tables and Edge Function**

Under **Database Schema → Remote Database (Supabase)**, add:

```markdown
- Additional tables for SP-2 (v0.4.0):
  - `user_agreements` — versioned EULA acceptance
  - `pin_reports` — user-filed reports on pins (service-role read only)
  - `blocked_users` — per-user blocklist (blocker_id, blocked_id)
  - `pins.name` has a `CHECK (char_length(name) <= 60)` constraint
```

Under a new **Edge Functions** section (immediately after **Remote Database**):

```markdown
### Edge Functions (Supabase)

- `send-moderation-email` — webhook target fired on `INSERT` into
  `pin_reports` or `blocked_users`. Sends the moderator a formatted
  plaintext email via Resend. See `docs/MODERATION.md` and
  `docs/DEPLOY.md`.
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(sp2): mark EULA + moderation infrastructure as implemented"
```

---

## Self-Review Checklist

- [ ] All four migrations (`004`, `005`, `006`, `007`) exist in `supabase/migrations/` and are applied to the live DB (Tasks 2–6).
- [ ] `ProfanityFilter` tests are green (Task 7); `PinDialog` enforces 60-char cap + profanity check (Task 8).
- [ ] `AgreementsRepository` + `ModerationRepository` exist with both interfaces and impls (Tasks 9, 10).
- [ ] `BlocklistService` tests are green; filter is applied in `MapViewModel`; changes notify `MapScreen` immediately (Tasks 11, 12).
- [ ] `EulaModal` has both modes, tested (Task 13). `LoginScreen` signup is gated on the EULA checkbox (Task 14). `_AppRoot` shows passive modal on first launch and retroactive modal for authenticated users without an `user_agreements` row (Task 15).
- [ ] `ReportPinDialog` tested (Task 16). `PinDialog` conditional Report/Block buttons tested (Task 17). `MapScreen` wires both handlers with success/failure snackbars (Task 18).
- [ ] `send-moderation-email` Edge Function exists, is deployed, webhooks fire, developer receives emails on report and block (Tasks 19, 20).
- [ ] `docs/MODERATION.md` and `docs/DEPLOY.md` exist (Tasks 21, 22).
- [ ] Manual end-to-end exercised on Android emulator (Task 23).
- [ ] `CLAUDE.md` updated (Task 24).

## Verification

Final gate before handing off to SP-3:

```bash
flutter analyze
flutter test
```

Both must be clean. Webhooks must be firing (smoke-tested in Task 20 Step 4). Then push the branch and move to SP-3.
