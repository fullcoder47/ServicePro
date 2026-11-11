-- ServicePro: exclusive Super Admin control over organization billing blocks.
-- Run once in Supabase SQL Editor BEFORE deploying the updated Flutter app.
-- Existing subscriptions/payments are preserved. No user data is removed.
begin;

alter table public.subscriptions
  add column if not exists status_before_block text;

-- Prevent staff from inserting a forged 'active' subscription for themselves.
-- Trial creation must go via the existing ensure_company_subscription RPC.
drop policy if exists "subscriptions insert super" on public.subscriptions;
create policy "subscriptions insert super"
  on public.subscriptions for insert to authenticated
  with check (public.is_super_admin());

-- Immutable history of actual Super Admin block/unblock operations.
create table if not exists public.billing_block_audit (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  actor_id uuid not null,
  previous_status text not null,
  new_status text not null,
  created_at timestamptz not null default now()
);
alter table public.billing_block_audit enable row level security;
drop policy if exists "billing block audit super read" on public.billing_block_audit;
create policy "billing block audit super read"
  on public.billing_block_audit for select to authenticated
  using (public.is_super_admin());
revoke all on public.billing_block_audit from anon, authenticated;
grant select on public.billing_block_audit to authenticated;

-- Atomic transition: a manual block is never cleared by merely adding a payment.
-- Unblocking restores the previous subscription status, unless its term expired.
create or replace function public.set_company_billing_block(
  p_company_id uuid,
  p_blocked boolean
) returns public.subscriptions
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_sub public.subscriptions%rowtype;
  v_old_status text;
  v_new_status text;
begin
  if auth.uid() is null or not public.is_super_admin() then
    raise exception 'billing_access_denied' using errcode = '42501';
  end if;
  if p_company_id is null or p_blocked is null then
    raise exception 'billing_invalid_request';
  end if;

  select * into v_sub from public.subscriptions
  where company_id = p_company_id for update;
  if not found then
    raise exception 'billing_subscription_missing';
  end if;

  v_old_status := v_sub.status;
  if p_blocked then
    if v_sub.status = 'blocked' then return v_sub; end if;
    v_new_status := 'blocked';
    update public.subscriptions
      set status = 'blocked', status_before_block = v_old_status,
          updated_at = clock_timestamp()
      where id = v_sub.id returning * into v_sub;
  else
    if v_sub.status <> 'blocked' then return v_sub; end if;
    v_new_status := coalesce(v_sub.status_before_block,
      case when v_sub.current_period_end > now() then 'active'
           when v_sub.trial_ends_at > now() then 'trial'
           else 'expired' end);
    -- Do not revive an already expired paid/trial period.
    if v_new_status = 'active' and v_sub.current_period_end is not null
       and v_sub.current_period_end <= now() then v_new_status := 'expired'; end if;
    if v_new_status = 'trial' and v_sub.trial_ends_at is not null
       and v_sub.trial_ends_at <= now() then v_new_status := 'expired'; end if;
    update public.subscriptions
      set status = v_new_status, status_before_block = null,
          updated_at = clock_timestamp()
      where id = v_sub.id returning * into v_sub;
  end if;

  insert into public.billing_block_audit(company_id, actor_id, previous_status, new_status)
  values (p_company_id, auth.uid(), v_old_status, v_sub.status);
  return v_sub;
end;
$$;
revoke all on function public.set_company_billing_block(uuid, boolean) from public;
revoke all on function public.set_company_billing_block(uuid, boolean) from anon;
grant execute on function public.set_company_billing_block(uuid, boolean) to authenticated;

-- Backend mutation guard: changing the UI cannot bypass a Super Admin block.
-- Only director/admin/worker members of a blocked company are stopped.
-- Residents, service-role background processes and Super Admin are unaffected.
create or replace function public.reject_blocked_company_writes()
returns trigger language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_caller_company uuid;
  v_caller_role text;
begin
  if auth.uid() is null then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;
  select role, company_id into v_caller_role, v_caller_company
  from public.profiles where id = auth.uid();
  if v_caller_role in ('director', 'admin', 'worker')
     and exists (select 1 from public.subscriptions s
                 where s.company_id = v_caller_company and s.status = 'blocked') then
    raise exception 'company_billing_blocked' using errcode = '42501';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

-- The guards are idempotent. They protect the existing operational tables
-- without altering any SELECT policies, subscriptions or payment history.
do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'companies', 'profiles', 'buildings', 'tickets',
    'notifications', 'device_tokens',
    'chat_rooms', 'chat_room_members', 'chat_messages',
    'chat_message_reads', 'chat_typing', 'chat_preferences', 'chat_reactions',
    'worker_payroll', 'worker_ratings', 'resident_addresses'
  ] loop
    if to_regclass(format('public.%I', v_table)) is not null then
      execute format('drop trigger if exists billing_block_write_guard on public.%I', v_table);
      execute format('create trigger billing_block_write_guard '
                     'before insert or update or delete on public.%I '
                     'for each row execute function public.reject_blocked_company_writes()', v_table);
    end if;
  end loop;
end;
$$;

notify pgrst, 'reload schema';
commit;
