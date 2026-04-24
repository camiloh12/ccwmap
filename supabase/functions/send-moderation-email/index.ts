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
