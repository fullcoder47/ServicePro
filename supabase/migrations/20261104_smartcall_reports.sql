-- ServicePro: SmartCall report-only integration.
-- No existing ServicePro tables or policies are modified.

create table if not exists public.smartcall_campaigns (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  external_group_id bigint unique,
  group_name text not null check (char_length(trim(group_name)) between 1 and 160),
  group_name_key text generated always as (lower(btrim(group_name))) stored,
  created_at timestamptz not null default now(),
  unique (group_name_key),
  unique (id, company_id)
);
create index if not exists smartcall_campaign_company_idx on public.smartcall_campaigns(company_id);

-- Supports history ONLY when SmartCall supplies its reporting API or export.
-- Do not infer missed calls/audio files from the pressed-1 webhook.
create table if not exists public.smartcall_calls (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null,
  company_id uuid not null,
  external_call_id text,
  phone text not null check (char_length(phone) between 7 and 30),
  status text not null default 'unknown' check (status in ('pending','sent','answered','unanswered','failed','cancelled','unknown')),
  dialed_at timestamptz,
  answered boolean,
  pressed_one boolean,
  duration_seconds integer check (duration_seconds is null or duration_seconds >= 0),
  operator_name text,
  recording_url text check (recording_url is null or left(recording_url, 8) = 'https://'),
  source text not null default 'provider_api' check (source in ('provider_api','verified_import')),
  last_synced_at timestamptz not null default now(),
  foreign key (campaign_id, company_id) references public.smartcall_campaigns(id,company_id) on delete cascade,
  unique (campaign_id,external_call_id)
);
create index if not exists smartcall_calls_company_time_idx on public.smartcall_calls(company_id,dialed_at desc);

create table if not exists public.smartcall_pressed_one_events (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null,
  company_id uuid not null,
  phone text not null check (char_length(phone) between 7 and 30),
  operator_name text,
  call_duration_seconds integer check (call_duration_seconds is null or call_duration_seconds >= 0),
  clicked_at timestamptz not null,
  event_hash text not null unique check (char_length(event_hash) = 64),
  received_at timestamptz not null default now(),
  foreign key (campaign_id, company_id) references public.smartcall_campaigns(id,company_id) on delete cascade
);
create index if not exists smartcall_pressed_company_time_idx on public.smartcall_pressed_one_events(company_id,clicked_at desc);

-- An official report API can later feed daily summaries. Not filled from webhook.
create table if not exists public.smartcall_campaign_snapshots (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null,
  company_id uuid not null,
  total_calls integer not null check (total_calls >= 0),
  answered_calls integer not null check (answered_calls >= 0),
  pressed_one_calls integer not null check (pressed_one_calls >= 0),
  snapshot_at timestamptz not null default now(),
  source text not null check (source in ('provider_api','verified_import')),
  foreign key (campaign_id, company_id) references public.smartcall_campaigns(id,company_id) on delete cascade,
  check (answered_calls <= total_calls),
  check (pressed_one_calls <= answered_calls)
);
create index if not exists smartcall_snapshot_campaign_time_idx on public.smartcall_campaign_snapshots(campaign_id,snapshot_at desc);

-- The raw secret never appears in the application database or application bundle.
-- A super admin receives the URL token ONCE by calling a protected RPC.
create table if not exists public.smartcall_webhook_keys (
  id uuid primary key default gen_random_uuid(),
  token_hash text not null unique check (char_length(token_hash) = 64),
  enabled boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.smartcall_campaigns enable row level security;
alter table public.smartcall_calls enable row level security;
alter table public.smartcall_pressed_one_events enable row level security;
alter table public.smartcall_campaign_snapshots enable row level security;
alter table public.smartcall_webhook_keys enable row level security;

revoke all on public.smartcall_campaigns, public.smartcall_calls,
  public.smartcall_pressed_one_events, public.smartcall_campaign_snapshots,
  public.smartcall_webhook_keys from anon, authenticated;
grant select on public.smartcall_campaigns, public.smartcall_calls,
  public.smartcall_pressed_one_events, public.smartcall_campaign_snapshots to authenticated;
grant insert, update, delete on public.smartcall_campaigns to authenticated;

create policy smartcall_campaign_read on public.smartcall_campaigns for select to authenticated
  using ( (select public.is_super_admin()) or
    (company_id = (select public.my_company_id()) and (select public.my_role()) in ('director','admin')) );
create policy smartcall_campaign_super_insert on public.smartcall_campaigns for insert to authenticated
  with check ((select public.is_super_admin()));
create policy smartcall_campaign_super_update on public.smartcall_campaigns for update to authenticated
  using ((select public.is_super_admin())) with check ((select public.is_super_admin()));
create policy smartcall_campaign_super_delete on public.smartcall_campaigns for delete to authenticated
  using ((select public.is_super_admin()));

create policy smartcall_call_read on public.smartcall_calls for select to authenticated
  using ((select public.is_super_admin()) or
    (company_id = (select public.my_company_id()) and (select public.my_role()) in ('director','admin')));
create policy smartcall_pressed_read on public.smartcall_pressed_one_events for select to authenticated
  using ((select public.is_super_admin()) or
    (company_id = (select public.my_company_id()) and (select public.my_role()) in ('director','admin')));
create policy smartcall_snapshot_read on public.smartcall_campaign_snapshots for select to authenticated
  using ((select public.is_super_admin()) or
    (company_id = (select public.my_company_id()) and (select public.my_role()) in ('director','admin')));
-- Intentionally NO end-user policies for webhook keys or imported call writes.

create or replace function public.smartcall_issue_webhook_token()
returns text language plpgsql security definer set search_path = '' as $$
declare
  v_token text;
begin
  if auth.uid() is null or not public.is_super_admin() then
    raise exception 'Only a super admin can configure SmartCall webhooks';
  end if;
  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.smartcall_webhook_keys(token_hash)
  values (encode(extensions.digest(v_token::bytea,'sha256'),'hex'));
  return v_token;
end;
$$;
revoke all on function public.smartcall_issue_webhook_token() from public, anon;
grant execute on function public.smartcall_issue_webhook_token() to authenticated;

comment on table public.smartcall_pressed_one_events is
  'Only SmartCall operator-connected pressed-1 events, not the full call history.';
