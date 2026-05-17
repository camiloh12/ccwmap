/// The single Supabase auth user that owns every pre-populated pin.
///
/// This UUID is identical in prod and staging — both Supabase projects had
/// the user provisioned via `auth.admin.createUser({ id: <this UUID>, ... })`
/// so app code never has to branch on environment.
///
/// See docs/superpowers/specs/2026-05-10-pre-populate-pins-design.md §3.
const String kSystemUserId = '81775f8b-1a6a-47d6-b793-e9ab7e38634e';
