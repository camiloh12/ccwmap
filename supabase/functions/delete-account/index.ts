// Supabase Edge Function: delete-account
//
// Authenticated-user self-deletion. The caller authenticates via JWT in
// the Authorization header; the function extracts the user id and calls
// supabase.auth.admin.deleteUser with the service-role key.
//
// No admin role check is required: callers can only delete themselves.
// Foreign-key cascades handle related rows:
//   user_agreements   ON DELETE CASCADE
//   blocked_users     ON DELETE CASCADE (both blocker_id and blocked_id)
//   pin_reports       reporter_id ON DELETE SET NULL
//   pins              created_by  ON DELETE SET NULL (preserves pins)

import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) {
    return new Response("Missing bearer token", { status: 401 });
  }

  // Identify the caller using the anon key + the caller's JWT. getUser
  // validates the JWT and returns the user it belongs to.
  const userClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: auth } },
  });

  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData.user) {
    return new Response("Invalid token", { status: 401 });
  }
  const userId = userData.user.id;

  // Use the service-role client for the admin delete.
  const adminClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { error: delErr } = await adminClient.auth.admin.deleteUser(userId);
  if (delErr) {
    return new Response(`Delete failed: ${delErr.message}`, { status: 500 });
  }

  return new Response(JSON.stringify({ ok: true, user_id: userId }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
