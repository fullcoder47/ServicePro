-- ServicePro AI: Microsoft Store 11.16 report & developer review queue.
-- Adds a NEW table; does not modify existing billing/chat/notifications tables.
-- Run in the Supabase SQL Editor once, before releasing the updated app.

create table if not exists public.ai_content_reports (
    id uuid primary key default gen_random_uuid(),
    reporter_user_id uuid not null default auth.uid(),
    ai_response text not null check (char_length(ai_response) between 1 and 200000),
    user_prompt text check (user_prompt is null or char_length(user_prompt) <= 3000),
    reason text not null check (
        reason in ('inaccurate', 'harmful', 'offensive', 'privacy', 'other')
    ),
    details text check (details is null or char_length(details) <= 500),
    status text not null default 'pending'
        check (status in ('pending', 'reviewing', 'resolved', 'dismissed')),
    reviewer_notes text,
    reviewed_at timestamptz,
    created_at timestamptz not null default now()
);

create index if not exists ai_content_reports_pending_idx
    on public.ai_content_reports (status, created_at desc);

alter table public.ai_content_reports enable row level security;

-- Reports are write-only to clients. They cannot read other users' reports,
-- edit moderation results, or mark their own reports as resolved.
revoke all on table public.ai_content_reports from anon, authenticated;
grant insert (
    reporter_user_id, ai_response, user_prompt, reason, details
) on table public.ai_content_reports to authenticated;

drop policy if exists ai_content_reports_authenticated_insert
    on public.ai_content_reports;
create policy ai_content_reports_authenticated_insert
    on public.ai_content_reports
    for insert to authenticated
    with check (reporter_user_id = (select auth.uid())
                and status = 'pending'
                and reviewer_notes is null
                and reviewed_at is null);

-- Developers review reports in Supabase Dashboard > Table Editor >
-- public.ai_content_reports using an authorized dashboard account.
-- Status and reviewer notes are edited there by project admins, NOT by users.
