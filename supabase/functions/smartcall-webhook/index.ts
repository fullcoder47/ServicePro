// Incoming SmartCall webhook. This function DOES NOT initiate calls.
// SmartCall documents this callback only for the "pressed 1 + spoke to an
// operator" case; it cannot report all calls or provide audio recordings.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const json = (status: number, value: Record<string, unknown>) =>
  new Response(JSON.stringify(value), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  });

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (part) => part.toString(16).padStart(2, '0')).join('');
}

function clickedAt(value: string): string | null {
  // SmartCall sends Tashkent-local timestamps without a timezone.
  const input = /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/.test(value)
    ? `${value.replace(' ', 'T')}+05:00`
    : value;
  const date = new Date(input);
  return Number.isFinite(date.getTime()) ? date.toISOString() : null;
}

Deno.serve(async (request) => {
  if (request.method !== 'POST') return json(405, { error: 'method_not_allowed' });

  const token = new URL(request.url).searchParams.get('token') ?? '';
  if (!/^[a-f0-9]{64}$/.test(token)) return json(401, { error: 'unauthorized' });
  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !serviceKey) return json(503, { error: 'not_configured' });
  const db = createClient(supabaseUrl, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const hashedToken = await sha256(token);
  const { data: validKey, error: keyError } = await db
    .from('smartcall_webhook_keys')
    .select('id')
    .eq('token_hash', hashedToken)
    .eq('enabled', true)
    .maybeSingle();
  if (keyError) return json(503, { error: 'database_unavailable' });
  if (!validKey) return json(401, { error: 'unauthorized' });

  if (Number(request.headers.get('content-length') ?? '0') > 8192) {
    return json(413, { error: 'payload_too_large' });
  }
  const rawBody = await request.text();
  if (rawBody.length > 8192) return json(413, { error: 'payload_too_large' });

  let data: Record<string, unknown>;
  try {
    const contentType = request.headers.get('content-type') ?? '';
    data = contentType.includes('application/json')
      ? JSON.parse(rawBody)
      : Object.fromEntries(new URLSearchParams(rawBody));
    if (!data || Array.isArray(data) || typeof data !== 'object') throw Error('bad shape');
  } catch (_) {
    return json(400, { error: 'invalid_body' });
  }

  const phone = String(data.phone ?? '').trim();
  const groupName = String(data.groupName ?? '').trim();
  const operator = String(data.operator ?? '').trim();
  const dateText = String(data.clickDate ?? '').trim();
  const duration = Number(data.callDuration);
  const timestamp = clickedAt(dateText);
  if (!/^\+?[0-9\s()-]{7,30}$/.test(phone) || !groupName || groupName.length > 160 ||
      operator.length > 160 || !Number.isInteger(duration) || duration < 0 ||
      duration > 86400 || !timestamp) {
    return json(400, { error: 'invalid_event' });
  }

  // Globally unique group names prevent accidental cross-company assignment.
  const { data: campaign, error: campaignError } = await db
    .from('smartcall_campaigns')
    .select('id,company_id')
    .eq('group_name_key', groupName.toLowerCase())
    .maybeSingle();
  if (campaignError) return json(503, { error: 'database_unavailable' });
  if (!campaign) return json(422, { error: 'campaign_not_mapped' });

  const eventHash = await sha256([
    campaign.id, phone, operator, timestamp, duration.toString(),
  ].join('\x1f'));
  const { error: insertError } = await db.from('smartcall_pressed_one_events').insert({
    company_id: campaign.company_id,
    campaign_id: campaign.id,
    phone,
    operator_name: operator || null,
    call_duration_seconds: duration,
    clicked_at: timestamp,
    event_hash: eventHash,
  });
  if (insertError && insertError.code !== '23505') {
    return json(503, { error: 'write_failed' });
  }
  return json(200, { ok: true, duplicate: insertError?.code === '23505' });
});
