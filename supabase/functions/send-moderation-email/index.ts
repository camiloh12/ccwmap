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
// timestamp, a deep link into Supabase Studio) and ships it via Brevo.

const BREVO_API_KEY = Deno.env.get("BREVO_API_KEY") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const MOD_FROM = Deno.env.get("MOD_FROM") ?? "moderation@kyberneticlabs.com";
const MOD_FROM_NAME = Deno.env.get("MOD_FROM_NAME") ?? "CCW Map Moderation";
const MOD_TO = Deno.env.get("MOD_TO") ?? "camilo@kyberneticlabs.com";

console.log(
  `send-moderation-email boot: ` +
    `BREVO_API_KEY=${BREVO_API_KEY ? "[set len " + BREVO_API_KEY.length + "]" : "[MISSING]"} ` +
    `SUPABASE_URL=${SUPABASE_URL ? "[set]" : "[MISSING]"} ` +
    `MOD_FROM=${MOD_FROM} MOD_FROM_NAME=${MOD_FROM_NAME} MOD_TO=${MOD_TO}`,
);

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
  if (!BREVO_API_KEY) {
    throw new Error("BREVO_API_KEY secret is not set");
  }
  console.log(`sendEmail: POST api.brevo.com subject="${subject}" from=${MOD_FROM} to=${MOD_TO}`);
  const res = await fetch("https://api.brevo.com/v3/smtp/email", {
    method: "POST",
    headers: {
      "accept": "application/json",
      "content-type": "application/json",
      "api-key": BREVO_API_KEY,
    },
    body: JSON.stringify({
      sender: { name: MOD_FROM_NAME, email: MOD_FROM },
      to: [{ email: MOD_TO }],
      subject,
      textContent: body,
    }),
  });
  const responseBody = await res.text();
  console.log(`Brevo response: status=${res.status} body=${responseBody}`);
  if (!res.ok) {
    throw new Error(`Brevo error ${res.status}: ${responseBody}`);
  }
}

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

// GET|POST /health — verifies BREVO_API_KEY still authenticates against Brevo.
//
// Called monthly by .github/workflows/brevo-keepalive.yml for two reasons:
//   1. Brevo deactivates API keys after 3 months with no API calls. Moderation
//      traffic is naturally near-zero, so a perfectly healthy key looks
//      abandoned — which is how the original ccwmap-mod key died silently,
//      taking pin_reports/blocked_users alerts with it. This call counts as
//      usage and resets that clock.
//   2. A dead key otherwise surfaces only when a real report arrives and the
//      email never lands. This turns that into a failed workflow run.
//
// /v3/account is read-only: it sends nothing and burns no email credits.
// Pass ?send=1 to additionally send a real heartbeat email, which exercises the
// full path (key + verified sender + credits) rather than auth alone.
async function healthCheck(send: boolean): Promise<Response> {
  if (!BREVO_API_KEY) {
    return json(500, { ok: false, error: "BREVO_API_KEY secret is not set" });
  }

  const res = await fetch("https://api.brevo.com/v3/account", {
    headers: { "accept": "application/json", "api-key": BREVO_API_KEY },
  });
  const body = await res.text();

  if (!res.ok) {
    console.error(`healthcheck: Brevo rejected the key — ${res.status}: ${body || "(empty body)"}`);
    return json(500, {
      ok: false,
      check: "brevo-account",
      status: res.status,
      error: body || "(empty body)",
    });
  }

  let plan: unknown = null;
  try {
    plan = (JSON.parse(body) as { plan?: unknown }).plan ?? null;
  } catch {
    // Brevo changed the response shape; auth still succeeded, which is the point.
  }
  console.log(`healthcheck: Brevo key OK (${res.status})`);

  if (!send) {
    return json(200, { ok: true, check: "brevo-account", status: res.status, plan });
  }

  try {
    await sendEmail(
      "[CCW Map] Moderation email heartbeat",
      [
        "This is an automated monthly heartbeat from send-moderation-email.",
        "",
        "It confirms the Brevo key, the verified sender, and email credits are",
        "all working — meaning a real pin report or user block would reach you.",
        "",
        "Nothing to action.",
      ].join("\n"),
    );
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    console.error(`healthcheck: heartbeat send failed — ${message}`);
    return json(500, { ok: false, check: "brevo-send", error: message });
  }

  return json(200, { ok: true, check: "brevo-send", sentTo: MOD_TO, plan });
}

const SYSTEM_USER_ID = "81775f8b-1a6a-47d6-b793-e9ab7e38634e";
const PROD_PROJECT_REF = "gqbxloaqamokbolcvesg";

const REASON_LABELS: Record<string, string> = {
  CLOSED: "Closed or no longer there",
  WRONG_LOCATION: "Wrong location",
  NOT_CATEGORY: "Wrong category",
  DUPLICATE: "Duplicate",
  OTHER: "Something else",
  INACCURATE: "Inaccurate",
  OFFENSIVE: "Offensive",
  SPAM: "Spam",
};

// Mirrors sourceLabel() in lib/presentation/widgets/pin_provenance.dart.
const SOURCE_LABELS: Record<string, string> = {
  nces: "public school records (NCES)",
  ipeds: "college records (IPEDS)",
  gsa: "federal property records (GSA)",
  hifld_courts: "courthouse records (HIFLD)",
  hifld_military: "military site records (HIFLD/USACE)",
  faa: "FAA airport records",
  osm: "OpenStreetMap",
};

function orNone(v: unknown): string {
  return v === null || v === undefined || v === "" ? "(none)" : String(v);
}

function formatImportedReport(r: Record<string, unknown>): { subject: string; body: string } {
  const reason = String(r.reason);
  const reasonLabel = REASON_LABELS[reason] ?? reason;
  const source = String(r.pin_source ?? "");
  const sourceLabel = SOURCE_LABELS[source] ?? "public records";
  const subject = `[CCW Map] Imported pin reported: ${reasonLabel} (${orNone(r.pin_source)})`;
  const lat = orNone(r.pin_latitude);
  const lng = orNone(r.pin_longitude);
  const target = SUPABASE_URL.includes(PROD_PROJECT_REF) ? "prod" : "staging";
  const body = [
    `report_id:  ${r.id}`,
    `reason:     ${reasonLabel}`,
    `note:       ${orNone(r.note)}`,
    `reporter:   ${r.reporter_id ?? "anonymous"}`,
    `created_at: ${r.created_at}`,
    ``,
    `pin name:   ${orNone(r.pin_name)}`,
    `dataset:    ${sourceLabel} (${orNone(r.pin_source)})`,
    `record id:  ${orNone(r.pin_source_external_id)}`,
    `tag:        ${orNone(r.pin_restriction_tag)}`,
    `confidence: ${orNone(r.pin_confidence)}`,
    `citation:   ${orNone(r.pin_legal_citation)}`,
    `map:        https://www.openstreetmap.org/?mlat=${lat}&mlon=${lng}#map=18/${lat}/${lng}`,
    ``,
    `Resolve: GitHub → Actions → Resolve pin report → Run workflow`,
    `  target:    ${target}`,
    `  report_id: ${r.id}`,
    `  action:    remove | move | dismiss`,
    `  move only: latitude / longitude (now ${lat}, ${lng})`,
    ``,
    `Studio:     ${studioLink("pin_reports", String(r.id))}`,
    `Pin row:    ${studioLink("pins", String(r.pin_id))}`,
  ].join("\n");
  return { subject, body };
}

function formatReport(r: Record<string, unknown>): { subject: string; body: string } {
  if (r.pin_created_by === SYSTEM_USER_ID) return formatImportedReport(r);
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
  console.log(`request: method=${req.method} url=${req.url}`);

  const url = new URL(req.url);
  if (url.pathname.endsWith("/health")) {
    try {
      return await healthCheck(url.searchParams.get("send") === "1");
    } catch (e) {
      const message = e instanceof Error ? e.message : String(e);
      console.error(`healthcheck error: ${message}`);
      return json(500, { ok: false, error: message });
    }
  }

  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }
  let payload: WebhookPayload;
  try {
    payload = await req.json();
  } catch (e) {
    console.error(`JSON parse failed: ${e}`);
    return new Response("Invalid JSON", { status: 400 });
  }
  console.log(`payload: table=${payload.table} type=${payload.type}`);

  try {
    let msg: { subject: string; body: string };
    if (payload.table === "pin_reports" && payload.type === "INSERT") {
      msg = formatReport(payload.record);
    } else if (payload.table === "blocked_users" && payload.type === "INSERT") {
      msg = formatBlock(payload.record);
    } else {
      console.log(`Ignoring ${payload.table}/${payload.type}`);
      return new Response(`Ignored ${payload.table}/${payload.type}`, {
        status: 200,
      });
    }
    await sendEmail(msg.subject, msg.body);
    console.log("Email sent successfully");
    return new Response("ok", { status: 200 });
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    const stack = e instanceof Error ? e.stack : "";
    console.error(`Handler error: ${message}\n${stack}`);
    return new Response(`error: ${message}`, { status: 500 });
  }
});
