-- ServicePro: resident billing account lookup requests.
-- Run AFTER SUBSCRIBER_BILLING_SETUP.sql. Existing billing data is not changed.
-- A typed address/account number is NOT proof of ownership. Only staff approval
-- can grant a resident access to private balances and transaction history.

create table if not exists public.billing_link_requests (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  lookup_method text not null check (lookup_method in ('account', 'address')),
  lookup_value text not null,
  suggested_account_id uuid references public.billing_accounts(id) on delete set null,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists billing_link_requests_company_pending_idx
  on public.billing_link_requests(company_id, status, created_at desc);
create index if not exists billing_link_requests_profile_idx
  on public.billing_link_requests(profile_id, created_at desc);

alter table public.billing_link_requests enable row level security;
revoke all on public.billing_link_requests from public, anon, authenticated;
grant select on public.billing_link_requests to authenticated;
drop policy if exists "billing link requests visible to owner or staff"
  on public.billing_link_requests;
create policy "billing link requests visible to owner or staff"
  on public.billing_link_requests for select to authenticated using (
    profile_id = (select auth.uid())
    or public.is_super_admin()
    or (company_id = public.my_company_id()
        and public.my_role() in ('director', 'admin'))
  );

-- Only a candidate suggestion for the reviewer: never an automatic link.
-- Whitespace/punctuation differences do not prevent finding likely matches.
create or replace function public.billing_address_key(p_text text)
returns text language sql immutable set search_path = '' as $$
  select regexp_replace(lower(coalesce(p_text, '')), '[^[:alnum:]]+', '', 'g');
$$;
revoke all on function public.billing_address_key(text) from public, anon;
grant execute on function public.billing_address_key(text) to authenticated;

create or replace function servicepro_private.billing_request_resident_link(
  p_method text, p_value text default null
) returns text language plpgsql security definer set search_path = '' as $$
declare
  v_profile public.profiles%rowtype;
  v_address public.resident_addresses%rowtype;
  v_value text;
  v_suggested uuid;
  v_match_count integer := 0;
  v_existing_owner uuid;
  v_street_key text;
  v_house_key text;
begin
  if (select auth.uid()) is null then raise exception 'authentication_required'; end if;
  select * into v_profile from public.profiles where id = (select auth.uid());
  if not found or v_profile.role <> 'user' or v_profile.company_id is null then
    raise exception 'resident_profile_required';
  end if;
  if p_method not in ('account', 'address') then raise exception 'invalid_lookup_method'; end if;

  if p_method = 'account' then
    v_value := trim(coalesce(p_value, ''));
    if length(v_value) < 4 or length(v_value) > 50 then
      raise exception 'invalid_account_number';
    end if;
    select a.id, a.resident_profile_id into v_suggested, v_existing_owner
    from public.billing_accounts a
    where a.company_id = v_profile.company_id and a.is_current
      and lower(trim(a.account_number)) = lower(v_value)
    limit 1;
    if v_existing_owner = (select auth.uid()) then
      return 'already_linked';
    end if;
  else
    select * into v_address from public.resident_addresses
    where profile_id = (select auth.uid());
    if not found or length(trim(v_address.street)) < 3
      or length(trim(v_address.house_number)) = 0 then
      raise exception 'resident_address_required';
    end if;
    v_value := concat_ws(', ', v_address.neighborhood, v_address.street,
      v_address.house_number);
    v_street_key := public.billing_address_key(v_address.street);
    v_house_key := public.billing_address_key(v_address.house_number);
    if length(v_street_key) < 3 or length(v_house_key) < 1 then
      raise exception 'invalid_resident_address';
    end if;
    select count(*), min(a.id::text)::uuid into v_match_count, v_suggested
    from public.billing_accounts a
    where a.company_id = v_profile.company_id and a.is_current
      and position(v_street_key in public.billing_address_key(a.address)) > 0
      and position(v_house_key in public.billing_address_key(a.address)) > 0;
    if v_match_count <> 1 then v_suggested := null; end if;
  end if;

  -- Keep previous requests as audit history instead of overwriting them.
  perform pg_advisory_xact_lock(hashtextextended((select auth.uid())::text, 0));
  if exists (
    select 1 from public.billing_link_requests
    where profile_id = (select auth.uid()) and status = 'pending'
      and lookup_method = p_method and lookup_value = v_value
  ) then return 'pending'; end if;
  if (select count(*) from public.billing_link_requests
      where profile_id = (select auth.uid())
        and created_at > now() - interval '24 hours') >= 10 then
    raise exception 'daily_request_limit';
  end if;
  update public.billing_link_requests set status = 'cancelled'
  where profile_id = (select auth.uid()) and status = 'pending';
  insert into public.billing_link_requests
    (company_id, profile_id, lookup_method, lookup_value, suggested_account_id)
  values (v_profile.company_id, (select auth.uid()), p_method, v_value, v_suggested);
  return 'pending';
end;
$$;

create or replace function servicepro_private.billing_review_resident_link(
  p_request_id uuid, p_account_id uuid, p_approve boolean
) returns void language plpgsql security definer set search_path = '' as $$
declare
  v_request public.billing_link_requests%rowtype;
  v_account public.billing_accounts%rowtype;
begin
  if (select auth.uid()) is null then raise exception 'authentication_required'; end if;
  select * into v_request from public.billing_link_requests
  where id = p_request_id for update;
  if not found then raise exception 'request_not_found'; end if;
  if v_request.status <> 'pending' then raise exception 'request_already_reviewed'; end if;
  if not coalesce((
    public.is_super_admin()
    or (v_request.company_id = public.my_company_id()
      and public.my_role() in ('director', 'admin'))
  ), false) then raise exception 'permission_denied'; end if;

  if p_approve then
    if p_account_id is null then raise exception 'account_selection_required'; end if;
    select * into v_account from public.billing_accounts
    where id = p_account_id and company_id = v_request.company_id and is_current
    for update;
    if not found then raise exception 'account_not_found_in_company'; end if;
    if v_account.resident_profile_id is not null
      and v_account.resident_profile_id <> v_request.profile_id then
      raise exception 'account_is_linked_to_another_resident';
    end if;
    if not exists (
      select 1 from public.profiles
      where id = v_request.profile_id and company_id = v_request.company_id
        and role = 'user'
    ) then raise exception 'resident_not_in_company'; end if;
    update public.billing_accounts
    set resident_profile_id = v_request.profile_id where id = v_account.id;
  end if;

  update public.billing_link_requests
  set status = case when p_approve then 'approved' else 'rejected' end,
      reviewed_by = (select auth.uid()), reviewed_at = now(),
      suggested_account_id = case when p_approve then p_account_id
                                  else suggested_account_id end
  where id = p_request_id;
end;
$$;

-- Keep SECURITY DEFINER code outside the exposed public schema. Only
-- security-invoker wrappers are reachable via the Data API.
create or replace function public.billing_request_resident_link(
  p_method text, p_value text default null
) returns text language sql security invoker set search_path = '' as $$
  select servicepro_private.billing_request_resident_link(p_method, p_value);
$$;
create or replace function public.billing_review_resident_link(
  p_request_id uuid, p_account_id uuid, p_approve boolean
) returns void language sql security invoker set search_path = '' as $$
  select servicepro_private.billing_review_resident_link(
    p_request_id, p_account_id, p_approve);
$$;

revoke all on function servicepro_private.billing_request_resident_link(text,text),
  servicepro_private.billing_review_resident_link(uuid,uuid,boolean)
  from public, anon, authenticated;
grant execute on function servicepro_private.billing_request_resident_link(text,text),
  servicepro_private.billing_review_resident_link(uuid,uuid,boolean)
  to authenticated;
revoke all on function public.billing_request_resident_link(text,text),
  public.billing_review_resident_link(uuid,uuid,boolean)
  from public, anon, authenticated;
grant execute on function public.billing_request_resident_link(text,text),
  public.billing_review_resident_link(uuid,uuid,boolean)
  to authenticated;
