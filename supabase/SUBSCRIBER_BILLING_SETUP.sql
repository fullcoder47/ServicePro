-- ServicePro / Abonentlar va Excel billing (2026-10-28)
-- Apply once in Supabase SQL Editor before enabling the new app pages.
-- Historical import rows are append-only; publishing an import never deletes them.

create extension if not exists pgcrypto;

create table if not exists public.billing_imports (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  filename text not null,
  sha256 text not null,
  storage_path text not null default '',
  status text not null default 'staging' check (status in ('staging', 'published', 'failed')),
  row_count integer not null default 0,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  published_at timestamptz,
  constraint billing_import_sha256_format check (sha256 ~ '^[0-9a-f]{64}$')
);
create index if not exists billing_imports_company_date_idx
  on public.billing_imports(company_id, created_at desc);

create table if not exists public.billing_accounts (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  account_number text not null,
  ordinal integer,
  region text not null default '',
  district text not null default '',
  address text not null default '',
  full_name text,
  subscriber_type text,
  cadastral_number text,
  contract_status text not null default '',
  balance numeric(18,2) not null default 0,
  resident_profile_id uuid references public.profiles(id) on delete set null,
  latest_import_id uuid references public.billing_imports(id) on delete set null,
  is_current boolean not null default true,
  updated_at timestamptz not null default now(),
  unique(company_id, account_number),
  constraint billing_account_number_format check (length(trim(account_number)) between 4 and 50)
);
create index if not exists billing_accounts_company_order_idx
  on public.billing_accounts(company_id, is_current, ordinal, account_number);
create index if not exists billing_accounts_resident_idx
  on public.billing_accounts(resident_profile_id) where resident_profile_id is not null;

create table if not exists public.billing_import_rows (
  import_id uuid not null references public.billing_imports(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  account_number text not null,
  ordinal integer,
  region text not null default '',
  district text not null default '',
  address text not null default '',
  full_name text,
  subscriber_type text,
  cadastral_number text,
  contract_status text not null default '',
  balance numeric(18,2) not null,
  source_row jsonb not null default '{}'::jsonb,
  primary key(import_id, account_number)
);
create index if not exists billing_import_rows_account_idx
  on public.billing_import_rows(company_id, account_number);

-- Optional source sheets, if a future Excel contains actual ledger or payments.
-- These records MUST NOT be inferred from changes in two account balances.
create table if not exists public.billing_ledger (
  id uuid primary key default gen_random_uuid(),
  import_id uuid not null references public.billing_imports(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  account_number text not null,
  year integer not null check (year between 2000 and 2200),
  month integer not null check (month between 1 and 12),
  area numeric(12,3),
  tariff numeric(18,2),
  opening_balance numeric(18,2),
  charged numeric(18,2),
  penalty numeric(18,2),
  paid numeric(18,2),
  recalculated numeric(18,2),
  closing_balance numeric(18,2),
  unique(import_id, account_number, year, month)
);
create index if not exists billing_ledger_account_idx
  on public.billing_ledger(company_id, account_number, year desc, month desc);

create table if not exists public.billing_transactions (
  id uuid primary key default gen_random_uuid(),
  import_id uuid not null references public.billing_imports(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  account_number text not null,
  kind text not null check (kind in ('payment','recalculation')),
  event_key text not null,
  occurred_at timestamptz not null,
  amount numeric(18,2) not null,
  method text,
  reference text,
  unique(import_id, account_number, kind, event_key)
);
create index if not exists billing_transactions_account_idx
  on public.billing_transactions(company_id, account_number, occurred_at desc);

alter table public.billing_imports enable row level security;
alter table public.billing_accounts enable row level security;
alter table public.billing_import_rows enable row level security;
alter table public.billing_ledger enable row level security;
alter table public.billing_transactions enable row level security;

revoke all on public.billing_imports, public.billing_accounts,
  public.billing_import_rows, public.billing_ledger, public.billing_transactions
  from anon, authenticated;
grant select on public.billing_imports, public.billing_accounts,
  public.billing_import_rows, public.billing_ledger, public.billing_transactions
  to authenticated;

drop policy if exists "billing imports read permitted" on public.billing_imports;
create policy "billing imports read permitted" on public.billing_imports
for select to authenticated using (
  public.is_super_admin() or
  (status = 'published' and (
    (company_id = public.my_company_id() and public.my_role() in ('director','admin')) or
    exists (select 1 from public.billing_accounts a
      where a.company_id = billing_imports.company_id
        and a.resident_profile_id = (select auth.uid()))
  ))
);

drop policy if exists "billing accounts read permitted" on public.billing_accounts;
create policy "billing accounts read permitted" on public.billing_accounts
for select to authenticated using (
  public.is_super_admin() or
  (company_id = public.my_company_id() and public.my_role() in ('director','admin')) or
  resident_profile_id = (select auth.uid())
);

drop policy if exists "billing rows read permitted" on public.billing_import_rows;
create policy "billing rows read permitted" on public.billing_import_rows
for select to authenticated using (
  exists (
    select 1 from public.billing_imports i
    where i.id = import_id and i.status = 'published'
      and (public.is_super_admin() or
        (i.company_id = public.my_company_id() and public.my_role() in ('director','admin')) or
        exists (select 1 from public.billing_accounts a where a.company_id = i.company_id
          and a.account_number = billing_import_rows.account_number
          and a.resident_profile_id = (select auth.uid())))
  )
);

drop policy if exists "billing ledger read permitted" on public.billing_ledger;
create policy "billing ledger read permitted" on public.billing_ledger
for select to authenticated using (
  exists (select 1 from public.billing_imports i where i.id = import_id and i.status = 'published')
  and (public.is_super_admin() or
    (company_id = public.my_company_id() and public.my_role() in ('director','admin')) or
    exists (select 1 from public.billing_accounts a where a.company_id = billing_ledger.company_id
      and a.account_number = billing_ledger.account_number
      and a.resident_profile_id = (select auth.uid())))
);

drop policy if exists "billing transactions read permitted" on public.billing_transactions;
create policy "billing transactions read permitted" on public.billing_transactions
for select to authenticated using (
  exists (select 1 from public.billing_imports i where i.id = import_id and i.status = 'published')
  and (public.is_super_admin() or
    (company_id = public.my_company_id() and public.my_role() in ('director','admin')) or
    exists (select 1 from public.billing_accounts a where a.company_id = billing_transactions.company_id
      and a.account_number = billing_transactions.account_number
      and a.resident_profile_id = (select auth.uid())))
);

-- Mutations are server-controlled, never exposed as direct REST table writes.
create or replace function public.billing_begin_import(
  p_company_id uuid, p_filename text, p_sha256 text
) returns public.billing_imports
language plpgsql security definer set search_path = '' as $$
declare result public.billing_imports;
begin
  if not public.is_super_admin() then raise exception 'Only super admin can import billing'; end if;
  if not exists(select 1 from public.companies where id = p_company_id) then
    raise exception 'Company not found';
  end if;
  if length(trim(p_filename)) < 1 or length(p_filename) > 255 then
    raise exception 'Invalid filename';
  end if;
  insert into public.billing_imports(company_id, filename, sha256, created_by)
    values(p_company_id, p_filename, p_sha256, (select auth.uid())) returning * into result;
  update public.billing_imports
    set storage_path = p_company_id::text || '/' || result.id::text || '/original.xlsx'
    where id = result.id returning * into result;
  return result;
end;
$$;

create or replace function public.billing_stage_rows(p_import_id uuid, p_rows jsonb)
returns integer language plpgsql security definer set search_path = '' as $$
declare v_import public.billing_imports; v_count int;
begin
  if not public.is_super_admin() then raise exception 'Only super admin can import billing'; end if;
  select * into v_import from public.billing_imports where id = p_import_id for update;
  if not found or v_import.status <> 'staging' then raise exception 'Import is not staging'; end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) not between 1 and 250 then
    raise exception 'Expected 1..250 rows';
  end if;
  insert into public.billing_import_rows(import_id, company_id, account_number, ordinal,
    region, district, address, full_name, subscriber_type, cadastral_number,
    contract_status, balance, source_row)
  select p_import_id, v_import.company_id, trim(r.account_number), r.ordinal,
    coalesce(r.region,''), coalesce(r.district,''), coalesce(r.address,''),
    nullif(trim(r.full_name),''), nullif(trim(r.subscriber_type),''),
    nullif(trim(r.cadastral_number),''), coalesce(r.contract_status,''),
    r.balance, r.source_row
  from jsonb_to_recordset(p_rows) as r(account_number text, ordinal int,
    region text, district text, address text, full_name text,
    subscriber_type text, cadastral_number text, contract_status text,
    balance numeric, source_row jsonb)
  where length(trim(r.account_number)) between 4 and 50 and r.balance is not null;
  get diagnostics v_count = row_count;
  if v_count <> jsonb_array_length(p_rows) then
    raise exception 'Invalid account number or balance';
  end if;
  return v_count;
end;
$$;

create or replace function public.billing_stage_ledger(p_import_id uuid, p_rows jsonb)
returns integer language plpgsql security definer set search_path = '' as $$
declare v_import public.billing_imports; v_count int;
begin
  if not public.is_super_admin() then raise exception 'Only super admin can import billing'; end if;
  select * into v_import from public.billing_imports where id=p_import_id for update;
  if not found or v_import.status <> 'staging' then raise exception 'Import is not staging'; end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) not between 1 and 250 then
    raise exception 'Expected 1..250 rows'; end if;
  insert into public.billing_ledger(import_id,company_id,account_number,year,month,area,tariff,
    opening_balance,charged,penalty,paid,recalculated,closing_balance)
  select p_import_id,v_import.company_id,trim(r.account_number),r.year,r.month,
    r.area,r.tariff,r.opening_balance,r.charged,r.penalty,r.paid,r.recalculated,r.closing_balance
  from jsonb_to_recordset(p_rows) as r(account_number text,year int,month int,area numeric,
    tariff numeric,opening_balance numeric,charged numeric,penalty numeric,paid numeric,
    recalculated numeric,closing_balance numeric);
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create or replace function public.billing_stage_transactions(p_import_id uuid, p_rows jsonb)
returns integer language plpgsql security definer set search_path = '' as $$
declare v_import public.billing_imports; v_count int;
begin
  if not public.is_super_admin() then raise exception 'Only super admin can import billing'; end if;
  select * into v_import from public.billing_imports where id=p_import_id for update;
  if not found or v_import.status <> 'staging' then raise exception 'Import is not staging'; end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) not between 1 and 250 then
    raise exception 'Expected 1..250 rows'; end if;
  insert into public.billing_transactions(import_id,company_id,account_number,kind,
    event_key,occurred_at,amount,method,reference)
  select p_import_id,v_import.company_id,trim(r.account_number),r.kind,
    r.event_key,r.occurred_at,r.amount,r.method,r.reference
  from jsonb_to_recordset(p_rows) as r(account_number text,kind text,event_key text,
    occurred_at timestamptz,amount numeric,method text,reference text)
  on conflict(import_id,account_number,kind,event_key) do nothing;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create or replace function public.billing_publish_import(p_import_id uuid, p_expected_rows integer)
returns integer language plpgsql security definer set search_path = '' as $$
declare v_import public.billing_imports; v_count int;
begin
  if not public.is_super_admin() then raise exception 'Only super admin can publish billing'; end if;
  select * into v_import from public.billing_imports where id=p_import_id for update;
  if not found or v_import.status <> 'staging' then raise exception 'Import is not staging'; end if;
  select count(*) into v_count from public.billing_import_rows where import_id=p_import_id;
  if p_expected_rows < 1 or v_count <> p_expected_rows then
    raise exception 'Import row mismatch: expected %, received %',p_expected_rows,v_count;
  end if;
  -- Serialize concurrent publications for one company.
  perform 1 from public.companies where id=v_import.company_id for update;
  if exists (select 1 from public.billing_ledger l
    where l.import_id=p_import_id and not exists (
      select 1 from public.billing_import_rows r
      where r.import_id=p_import_id and r.account_number=l.account_number)) then
    raise exception 'Monthly ledger includes an unknown account';
  end if;
  if exists (select 1 from public.billing_transactions t
    where t.import_id=p_import_id and not exists (
      select 1 from public.billing_import_rows r
      where r.import_id=p_import_id and r.account_number=t.account_number)) then
    raise exception 'Transactions include an unknown account';
  end if;
  -- Older subscribers remain stored but are no longer shown as current.
  update public.billing_accounts set is_current=false
    where company_id=v_import.company_id;
  insert into public.billing_accounts(company_id,account_number,ordinal,region,district,
    address,full_name,subscriber_type,cadastral_number,contract_status,balance,
    latest_import_id,is_current,updated_at)
  select v_import.company_id,r.account_number,r.ordinal,r.region,r.district,
    r.address,r.full_name,r.subscriber_type,r.cadastral_number,r.contract_status,
    r.balance,p_import_id,true,now()
  from public.billing_import_rows r where r.import_id=p_import_id
  on conflict(company_id,account_number) do update set
    ordinal=excluded.ordinal,region=excluded.region,district=excluded.district,
    address=excluded.address,
    full_name=coalesce(excluded.full_name,public.billing_accounts.full_name),
    subscriber_type=coalesce(excluded.subscriber_type,public.billing_accounts.subscriber_type),
    cadastral_number=coalesce(excluded.cadastral_number,public.billing_accounts.cadastral_number),
    contract_status=excluded.contract_status,balance=excluded.balance,
    latest_import_id=p_import_id,is_current=true,updated_at=now();
  update public.billing_imports set status='published',published_at=now(),row_count=v_count
    where id=p_import_id;
  return v_count;
end;
$$;

create or replace function public.billing_link_resident(p_account_id uuid, p_profile_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_company_id uuid;
begin
  select company_id into v_company_id from public.billing_accounts where id=p_account_id for update;
  if not found then raise exception 'Account not found'; end if;
  if not (public.is_super_admin() or
    (v_company_id=public.my_company_id() and public.my_role() in ('director','admin'))) then
    raise exception 'Insufficient permissions';
  end if;
  if p_profile_id is not null and not exists (
    select 1 from public.profiles where id=p_profile_id
      and company_id=v_company_id and role='user') then
    raise exception 'Resident must be in the same company';
  end if;
  update public.billing_accounts set resident_profile_id=p_profile_id where id=p_account_id;
end;
$$;

revoke execute on function public.billing_begin_import(uuid,text,text),
  public.billing_stage_rows(uuid,jsonb),public.billing_stage_ledger(uuid,jsonb),
  public.billing_stage_transactions(uuid,jsonb),public.billing_publish_import(uuid,integer),
  public.billing_link_resident(uuid,uuid) from public, anon;
grant execute on function public.billing_begin_import(uuid,text,text),
  public.billing_stage_rows(uuid,jsonb),public.billing_stage_ledger(uuid,jsonb),
  public.billing_stage_transactions(uuid,jsonb),public.billing_publish_import(uuid,integer),
  public.billing_link_resident(uuid,uuid) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('billing-imports','billing-imports',false,15728640,
  array['application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'])
on conflict(id) do nothing;
update storage.buckets set public=false, file_size_limit=15728640,
  allowed_mime_types=array['application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']
where id='billing-imports';

drop policy if exists "billing originals super read" on storage.objects;
create policy "billing originals super read" on storage.objects
for select to authenticated using(bucket_id='billing-imports' and public.is_super_admin());
drop policy if exists "billing originals super insert" on storage.objects;
create policy "billing originals super insert" on storage.objects
for insert to authenticated with check(bucket_id='billing-imports' and public.is_super_admin());

