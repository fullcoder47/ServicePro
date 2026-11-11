-- ServicePro: individual device/session management.
-- Run on a staging database first, then in Supabase SQL Editor in production.
-- This file is NOT applied automatically by the Flutter application.

begin;

create schema if not exists servicepro_private;

create table if not exists servicepro_private.session_devices (
  session_id uuid primary key references auth.sessions(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  installation_id text not null,
  platform text not null default 'unknown',
  device_label text not null default 'Nomaʼlum qurilma',
  app_version text,
  custom_name boolean not null default false,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  constraint servicepro_installation_id_len check (length(installation_id) between 16 and 64),
  constraint servicepro_device_label_len check (length(device_label) between 1 and 64)
);
create index if not exists servicepro_session_devices_user_idx
  on servicepro_private.session_devices (user_id, last_seen_at desc);
alter table servicepro_private.session_devices enable row level security;
revoke all on table servicepro_private.session_devices from public, anon, authenticated;

create table if not exists servicepro_private.session_security_events (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  actor_session_id uuid,
  target_session_id uuid not null,
  target_label text,
  action text not null check (action in ('revoke_one')),
  occurred_at timestamptz not null default now()
);
create index if not exists servicepro_session_events_user_idx
  on servicepro_private.session_security_events (user_id, occurred_at desc);
alter table servicepro_private.session_security_events enable row level security;
revoke all on table servicepro_private.session_security_events from public, anon, authenticated;

-- The authenticated user supplies ONLY a friendly display name and platform.
-- The real identity/session is taken from the server-verified JWT, never from
-- a client-supplied user_id/session_id.
create or replace function public.servicepro_session_touch(
  p_installation_id text,
  p_platform text,
  p_device_label text,
  p_app_version text default ''
) returns boolean
language plpgsql security definer set search_path = ''
as $fn$
declare
  v_uid uuid := auth.uid();
  v_session_id uuid;
  v_platform text;
  v_label text;
begin
  if v_uid is null or nullif(auth.jwt()->>'session_id','') is null then
    raise exception 'session_auth_required';
  end if;
  v_session_id := (auth.jwt()->>'session_id')::uuid;
  if not exists (select 1 from auth.sessions s
                 where s.id=v_session_id and s.user_id=v_uid) then
    raise exception 'session_revoked';
  end if;
  if p_installation_id is null or p_installation_id !~ '^[A-Za-z0-9_-]{16,64}$' then
    raise exception 'invalid_installation_id';
  end if;
  v_platform := case when p_platform in ('android','ios','windows','macos','linux','web')
                     then p_platform else 'unknown' end;
  v_label := left(regexp_replace(trim(coalesce(p_device_label,'')), '[[:cntrl:]]', '', 'g'), 64);
  if v_label = '' then v_label := 'Nomaʼlum qurilma'; end if;
  insert into servicepro_private.session_devices as d
    (session_id,user_id,installation_id,platform,device_label,app_version,last_seen_at)
  values (v_session_id,v_uid,p_installation_id,v_platform,v_label,left(coalesce(p_app_version,''),24),now())
  on conflict (session_id) do update
     set last_seen_at=now(),
         app_version=excluded.app_version,
         platform=excluded.platform,
         device_label=case when d.custom_name then d.device_label else excluded.device_label end;
  return true;
end;
$fn$;

create or replace function public.servicepro_session_rename(p_device_label text)
returns boolean language plpgsql security definer set search_path = ''
as $fn$
declare
  v_label text := left(regexp_replace(trim(coalesce(p_device_label,'')), '[[:cntrl:]]', '', 'g'), 64);
  v_updated integer;
begin
  if auth.uid() is null or nullif(auth.jwt()->>'session_id','') is null then
    raise exception 'session_auth_required';
  end if;
  if length(v_label) < 2 then raise exception 'device_name_too_short'; end if;
  update servicepro_private.session_devices
     set device_label=v_label,custom_name=true,last_seen_at=now()
   where user_id=auth.uid() and session_id=(auth.jwt()->>'session_id')::uuid;
  get diagnostics v_updated = row_count;
  return v_updated=1;
end;
$fn$;

create or replace function public.servicepro_my_sessions()
returns table (
  session_id uuid, device_label text, platform text, app_version text,
  login_at timestamptz, last_seen_at timestamptz, ip_address text,
  user_agent text, aal text, is_current boolean, is_online boolean
) language sql stable security definer set search_path = ''
as $fn$
  select s.id, coalesce(d.device_label,'Nomaʼlum qurilma'),
         coalesce(d.platform,'unknown'),coalesce(d.app_version,''),
         s.created_at,
         greatest(coalesce(d.last_seen_at,s.created_at),coalesce(s.updated_at,s.created_at)),
         host(s.ip), left(coalesce(s.user_agent,''),220),s.aal::text,
         s.id = nullif(auth.jwt()->>'session_id','')::uuid,
         d.last_seen_at >= now()-interval '3 minutes'
  from auth.sessions s
  left join servicepro_private.session_devices d on d.session_id=s.id and d.user_id=s.user_id
  where s.user_id=auth.uid() and auth.uid() is not null
    and exists (select 1 from auth.sessions mine
                where mine.id=nullif(auth.jwt()->>'session_id','')::uuid
                  and mine.user_id=auth.uid())
  order by (s.id = nullif(auth.jwt()->>'session_id','')::uuid) desc,
           greatest(coalesce(d.last_seen_at,s.created_at),coalesce(s.updated_at,s.created_at)) desc
  limit 100;
$fn$;

-- One-by-one revocation: only another session owned by the currently signed-in
-- user. Deleting auth.sessions cascades to its refresh tokens in the current
-- GoTrue schema. Test against your Supabase version before production rollout.
create or replace function public.servicepro_revoke_my_session(p_session_id uuid)
returns boolean language plpgsql security definer set search_path = ''
as $fn$
declare
  v_uid uuid := auth.uid();
  v_current uuid;
  v_label text;
  v_deleted uuid;
begin
  if v_uid is null or nullif(auth.jwt()->>'session_id','') is null then
    raise exception 'session_auth_required';
  end if;
  v_current := (auth.jwt()->>'session_id')::uuid;
  if not exists(select 1 from auth.sessions s where s.id=v_current and s.user_id=v_uid) then
    raise exception 'session_revoked';
  end if;
  if p_session_id is null or p_session_id=v_current then
    raise exception 'cannot_revoke_current_session';
  end if;
  select coalesce(d.device_label,'Nomaʼlum qurilma') into v_label
  from auth.sessions s left join servicepro_private.session_devices d on d.session_id=s.id
  where s.id=p_session_id and s.user_id=v_uid;
  if not found then return false; end if;
  delete from auth.sessions s
   where s.id=p_session_id and s.user_id=v_uid and s.id<>v_current
   returning s.id into v_deleted;
  if v_deleted is null then return false; end if;
  insert into servicepro_private.session_security_events
    (user_id,actor_session_id,target_session_id,target_label,action)
  values (v_uid,v_current,v_deleted,v_label,'revoke_one');
  return true;
end;
$fn$;

-- Lock down RPC execution: the functions themselves also verify auth.uid().
revoke all on function public.servicepro_session_touch(text,text,text,text) from public, anon;
revoke all on function public.servicepro_session_rename(text) from public, anon;
revoke all on function public.servicepro_my_sessions() from public, anon;
revoke all on function public.servicepro_revoke_my_session(uuid) from public, anon;
grant execute on function public.servicepro_session_touch(text,text,text,text) to authenticated;
grant execute on function public.servicepro_session_rename(text) to authenticated;
grant execute on function public.servicepro_my_sessions() to authenticated;
grant execute on function public.servicepro_revoke_my_session(uuid) to authenticated;

-- Extra protection for chat: a revoked JWT session cannot keep sending messages
-- via the existing chat_send_message SECURITY DEFINER RPC while its JWT lives.
-- Does not change messages inserted by internal service jobs without auth.uid().
create or replace function servicepro_private.require_active_chat_session()
returns trigger language plpgsql security definer set search_path = ''
as $fn$
begin
  if auth.uid() is not null then
    if nullif(auth.jwt()->>'session_id','') is null
       or not exists(select 1 from auth.sessions s
                     where s.id=(auth.jwt()->>'session_id')::uuid
                       and s.user_id=auth.uid()) then
      raise exception 'session_revoked';
    end if;
  end if;
  return new;
end;
$fn$;
revoke all on function servicepro_private.require_active_chat_session() from public, anon, authenticated;
drop trigger if exists servicepro_chat_session_guard on public.chat_messages;
create trigger servicepro_chat_session_guard before insert or update on public.chat_messages
for each row execute function servicepro_private.require_active_chat_session();

commit;

-- Verification queries after deployment (read-only):
-- select proname from pg_proc where proname like 'servicepro_%session%';
-- select tgname from pg_trigger where tgname='servicepro_chat_session_guard';
-- Test with two non-admin accounts: neither should list/revoke the other's sessions.
