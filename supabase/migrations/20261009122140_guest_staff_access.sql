-- Candidate migration. Test on staging before production.
-- Does not delete existing accounts, companies, tickets, messages or media.
begin;
create schema if not exists servicepro_private;
revoke all on schema servicepro_private from public;
grant usage on schema servicepro_private to anon, authenticated;

alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check check (role in ('super_admin','director','admin','worker','user'));
alter table public.profiles add column if not exists job_title text not null default '';

create table if not exists public.resident_addresses (
 profile_id uuid primary key references public.profiles(id) on delete cascade,
 neighborhood text not null, street text not null, house_number text not null
);
alter table public.resident_addresses enable row level security;
grant select,insert,update on public.resident_addresses to authenticated;
create policy "resident address own" on public.resident_addresses for all to authenticated
 using(profile_id=auth.uid() or public.is_super_admin())
 with check(profile_id=auth.uid() or public.is_super_admin());

create table if not exists servicepro_private.staff_invites (
 id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id) on delete cascade,
 role text not null check(role in ('director','admin','worker')), email text not null,
 first_name text not null, last_name text not null, code_hash text not null unique,
 created_by uuid not null references public.profiles(id), expires_at timestamptz not null default now()+interval '7 days',
 used_by uuid references public.profiles(id) on delete set null, used_at timestamptz
);
alter table servicepro_private.staff_invites enable row level security;
revoke all on servicepro_private.staff_invites from public, anon, authenticated;

-- Payroll is deliberately separate from profiles: residents cannot SELECT it.
create table if not exists public.worker_payroll (
 profile_id uuid primary key references public.profiles(id) on delete cascade,
 monthly_salary numeric(14,2) not null check(monthly_salary >= 0), updated_at timestamptz not null default now()
);
alter table public.worker_payroll enable row level security;
grant select,insert,update,delete on public.worker_payroll to authenticated;
create policy "payroll authorized read" on public.worker_payroll for select to authenticated using (
 public.is_super_admin() or profile_id=auth.uid() or (public.my_role() in ('director','admin') and exists(select 1 from public.profiles p where p.id=profile_id and p.company_id=public.my_company_id()))
);
create policy "payroll super write" on public.worker_payroll for all to authenticated using (public.is_super_admin()) with check(public.is_super_admin());

create table if not exists public.worker_ratings (
 ticket_id uuid primary key references public.tickets(id) on delete cascade,
 rated_by uuid not null references public.profiles(id) on delete cascade, worker_id uuid not null references public.profiles(id) on delete cascade,
 score integer not null check(score between 1 and 5), created_at timestamptz not null default now()
);
alter table public.worker_ratings enable row level security;
grant select,insert,update,delete on public.worker_ratings to authenticated;
create policy "ratings read authorized" on public.worker_ratings for select to authenticated using (
 public.is_super_admin() or rated_by=auth.uid() or worker_id=auth.uid()
);
create policy "ratings insert owner" on public.worker_ratings for insert to authenticated with check (
 rated_by=auth.uid() and exists(select 1 from public.tickets t where t.id=ticket_id and t.created_by=auth.uid() and t.completed_by=worker_id and t.status in ('completed','closed'))
);
create policy "ratings super delete" on public.worker_ratings for delete to authenticated using(public.is_super_admin());

-- A client may change its display/settings fields, never its identity or role.
create or replace function servicepro_private.protect_profile_identity() returns trigger language plpgsql set search_path='' as $$
begin
 if current_user in ('postgres','service_role','supabase_admin') or public.is_super_admin() then return new; end if;
 if new.id is distinct from old.id or new.role is distinct from old.role or new.company_id is distinct from old.company_id or new.email is distinct from old.email then
  raise exception 'Profile authorization fields cannot be changed';
 end if;
 return new;
end $$;
drop trigger if exists servicepro_profile_identity on public.profiles;
create trigger servicepro_profile_identity before update on public.profiles for each row execute function servicepro_private.protect_profile_identity();
drop policy if exists "profiles insert self" on public.profiles;
create policy "profiles insert self" on public.profiles for insert to authenticated with check (
 public.is_super_admin() or (id=auth.uid() and role='user' and company_id is not null)
);
drop policy if exists "companies insert director" on public.companies;
create policy "companies insert super" on public.companies for insert to authenticated with check(public.is_super_admin());

create or replace function servicepro_private.company_directory() returns table(id uuid,name text,created_at timestamptz)
language sql stable security definer set search_path='' as $$
 select c.id,c.name,c.created_at from public.companies c where c.is_active order by c.name
$$;

create or replace function servicepro_private.complete_resident(p_company_id uuid,p_first_name text,p_last_name text,p_phone text,p_neighborhood text,p_street text,p_house_number text,p_language text)
returns void language plpgsql security definer set search_path='' as $$
declare expected_email text; existing public.profiles;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if p_phone !~ '^998[0-9]{9}$' or length(trim(p_first_name))=0 or length(trim(p_last_name))=0 or length(trim(p_neighborhood))=0 or length(trim(p_street))=0 or length(trim(p_house_number))=0 then raise exception 'Required profile fields missing'; end if;
 if not exists(select 1 from public.companies where id=p_company_id and is_active) then raise exception 'Company unavailable'; end if;
 expected_email := 'user_' || replace(p_company_id::text,'-','') || '_' || p_phone || '@servicepro.local';
 if lower(coalesce(auth.jwt()->>'email','')) <> lower(expected_email) then raise exception 'Account mismatch'; end if;
 select * into existing from public.profiles where id=auth.uid();
 if found then
  if existing.role <> 'user' or existing.company_id is distinct from p_company_id then raise exception 'Account mismatch'; end if;
  return;
 end if;
 insert into public.profiles(id,company_id,role,first_name,last_name,phone,email,language)
 values(auth.uid(),p_company_id,'user',trim(p_first_name),trim(p_last_name),p_phone,expected_email,p_language);
 insert into public.resident_addresses(profile_id,neighborhood,street,house_number)
 values(auth.uid(),trim(p_neighborhood),trim(p_street),trim(p_house_number));
end $$;

create or replace function servicepro_private.create_staff_invite(p_company_id uuid,p_role text,p_email text,p_first_name text,p_last_name text)
returns text language plpgsql security definer set search_path='' as $$
declare code text; expected_email text;
begin
 if auth.uid() is null or not public.is_super_admin() then raise exception 'Super admin required'; end if;
 if p_role not in ('director','admin','worker') or trim(p_first_name)='' or trim(p_last_name)='' then raise exception 'Invalid staff identity'; end if;
 if not exists(select 1 from public.companies where id=p_company_id and is_active) then raise exception 'Company unavailable'; end if;
 expected_email := 'staff_'||substr(encode(sha256(convert_to(p_company_id::text||'|'||lower(trim(p_first_name))||'|'||lower(trim(p_last_name)),'UTF8')),'hex'),1,48)||'@servicepro.local';
 if p_email<>expected_email then raise exception 'Account mismatch'; end if;
 if exists(select 1 from public.profiles where email=p_email) then raise exception 'Staff account already exists'; end if;
 code := replace(gen_random_uuid()::text,'-','');
 -- Issuing another code revokes previous unused codes for this identity.
 delete from servicepro_private.staff_invites where email=p_email and used_at is null;
 insert into servicepro_private.staff_invites(company_id,role,email,first_name,last_name,code_hash,created_by)
 values(p_company_id,p_role,p_email,trim(p_first_name),trim(p_last_name),encode(sha256(convert_to(code,'UTF8')),'hex'),auth.uid());
 return code;
end $$;

create or replace function servicepro_private.check_staff_invite(p_company_id uuid,p_role text,p_email text,p_code text)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from servicepro_private.staff_invites where company_id=p_company_id and role=p_role and email=p_email and code_hash=encode(sha256(convert_to(p_code,'UTF8')),'hex') and used_at is null and expires_at>now()) then
  raise exception 'Invalid or expired invitation';
 end if;
 return true;
end $$;

create or replace function servicepro_private.claim_staff_invite(p_company_id uuid,p_role text,p_code text,p_first_name text,p_last_name text,p_job_title text,p_language text)
returns void language plpgsql security definer set search_path='' as $$
declare invite servicepro_private.staff_invites;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 select * into invite from servicepro_private.staff_invites where company_id=p_company_id and role=p_role and code_hash=encode(sha256(convert_to(p_code,'UTF8')),'hex') and used_at is null and expires_at>now() for update;
 if not found or lower(invite.email) <> lower(coalesce(auth.jwt()->>'email','')) or lower(invite.first_name)<>lower(trim(p_first_name)) or lower(invite.last_name)<>lower(trim(p_last_name)) then raise exception 'Invalid or expired invitation'; end if;
 if not exists(select 1 from public.companies where id=p_company_id and is_active) then raise exception 'Company unavailable'; end if;
 if p_role='worker' and length(trim(p_job_title))=0 then raise exception 'Job title required'; end if;
 if exists(select 1 from public.profiles where id=auth.uid()) then raise exception 'Profile already exists'; end if;
 insert into public.profiles(id,company_id,role,first_name,last_name,email,job_title,language)
 values(auth.uid(),p_company_id,p_role,invite.first_name,invite.last_name,invite.email,trim(p_job_title),p_language);
 update servicepro_private.staff_invites set used_by=auth.uid(),used_at=now() where id=invite.id;
end $$;

create or replace function servicepro_private.team_directory() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare me public.profiles; result jsonb;
begin
 select * into me from public.profiles where id=auth.uid();
 if not found then raise exception 'Authentication required'; end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',p.id,'first_name',p.first_name,'last_name',p.last_name,'avatar_url',p.avatar_url,'job_title',p.job_title,
  'completed_count',(select count(*) from public.tickets t where t.completed_by=p.id and t.status in ('completed','closed')),
  'busy',exists(select 1 from public.tickets t where t.accepted_by=p.id and t.status='in_progress'),
  'rating',(select round(avg(r.score)::numeric,1) from public.worker_ratings r where r.worker_id=p.id),
  'monthly_salary',case when me.role='super_admin' or me.id=p.id or (me.company_id=p.company_id and me.role in ('director','admin')) then (select w.monthly_salary from public.worker_payroll w where w.profile_id=p.id) else null end
 ) order by p.first_name),'[]'::jsonb) into result
 from public.profiles p where p.role='worker' and (me.role='super_admin' or p.company_id=me.company_id);
 return result;
end $$;

-- Residents only see their own tickets. Workers see company work queues.
drop policy if exists "tickets select visible" on public.tickets;
create policy "tickets select visible" on public.tickets for select to authenticated using (
 public.is_super_admin() or created_by=auth.uid() or (company_id=public.my_company_id() and public.my_role() in ('director','admin','worker'))
);
create or replace function servicepro_private.protect_resident_ticket() returns trigger language plpgsql set search_path='' as $$
begin
 if current_user in ('postgres','service_role','supabase_admin') or public.is_super_admin() or public.my_role() in ('director','admin') then return new; end if;
 if old.created_by<>auth.uid() or old.status<>'completed' or new.status<>'closed' or (to_jsonb(old)-'status') is distinct from (to_jsonb(new)-'status') then raise exception 'Ticket update not allowed'; end if;
 return new;
end $$;
drop trigger if exists servicepro_ticket_owner_guard on public.tickets;
create trigger servicepro_ticket_owner_guard before update on public.tickets for each row execute function servicepro_private.protect_resident_ticket();

create or replace function servicepro_private.transition_ticket(p_ticket_id uuid,p_complete boolean,p_description text,p_media text[])
returns public.tickets language plpgsql security definer set search_path='' as $$
declare me public.profiles; item public.tickets;
begin
 select * into me from public.profiles where id=auth.uid();
 if not found or me.role not in ('super_admin','director','admin','worker') then raise exception 'Staff required'; end if;
 select * into item from public.tickets where id=p_ticket_id for update;
 if not found or (me.role<>'super_admin' and me.company_id is distinct from item.company_id) then raise exception 'Ticket unavailable'; end if;
 if p_complete then
  if item.status<>'in_progress' or (me.role='worker' and item.accepted_by is distinct from me.id) then raise exception 'Ticket is not assigned to this worker'; end if;
  if trim(p_description)='' or coalesce(array_length(p_media,1),0)=0 then raise exception 'Completion text and media required'; end if;
  update public.tickets set status='completed',completed_by=me.id,completed_at=now(),completion_description=trim(p_description),completion_attachments=p_media where id=p_ticket_id returning * into item;
 else
  if item.status<>'new' then raise exception 'Ticket already accepted'; end if;
  update public.tickets set status='in_progress',accepted_by=me.id,accepted_at=now() where id=p_ticket_id returning * into item;
 end if;
 return item;
end $$;

create or replace function public.servicepro_company_directory() returns table(id uuid,name text,created_at timestamptz)
language sql security invoker set search_path='' as $$ select * from servicepro_private.company_directory() $$;
revoke all on function servicepro_private.company_directory() from public,anon,authenticated;
grant execute on function servicepro_private.company_directory() to anon,authenticated;
revoke all on function public.servicepro_company_directory() from public,anon,authenticated;
grant execute on function public.servicepro_company_directory() to anon,authenticated;

create or replace function public.servicepro_complete_resident(p_company_id uuid,p_first_name text,p_last_name text,p_phone text,p_neighborhood text,p_street text,p_house_number text,p_language text) returns void
language sql security invoker set search_path='' as $$ select servicepro_private.complete_resident(p_company_id,p_first_name,p_last_name,p_phone,p_neighborhood,p_street,p_house_number,p_language) $$;
revoke all on function servicepro_private.complete_resident(uuid,text,text,text,text,text,text,text) from public,anon,authenticated;
grant execute on function servicepro_private.complete_resident(uuid,text,text,text,text,text,text,text) to authenticated;
revoke all on function public.servicepro_complete_resident(uuid,text,text,text,text,text,text,text) from public,anon,authenticated;
grant execute on function public.servicepro_complete_resident(uuid,text,text,text,text,text,text,text) to authenticated;

create or replace function public.servicepro_create_staff_invite(p_company_id uuid,p_role text,p_email text,p_first_name text,p_last_name text) returns text
language sql security invoker set search_path='' as $$ select servicepro_private.create_staff_invite(p_company_id,p_role,p_email,p_first_name,p_last_name) $$;
revoke all on function servicepro_private.create_staff_invite(uuid,text,text,text,text) from public,anon,authenticated;
grant execute on function servicepro_private.create_staff_invite(uuid,text,text,text,text) to authenticated;
revoke all on function public.servicepro_create_staff_invite(uuid,text,text,text,text) from public,anon,authenticated;
grant execute on function public.servicepro_create_staff_invite(uuid,text,text,text,text) to authenticated;

create or replace function public.servicepro_check_staff_invite(p_company_id uuid,p_role text,p_email text,p_code text) returns boolean
language sql security invoker set search_path='' as $$ select servicepro_private.check_staff_invite(p_company_id,p_role,p_email,p_code) $$;
revoke all on function servicepro_private.check_staff_invite(uuid,text,text,text) from public,anon,authenticated;
grant execute on function servicepro_private.check_staff_invite(uuid,text,text,text) to anon,authenticated;
revoke all on function public.servicepro_check_staff_invite(uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.servicepro_check_staff_invite(uuid,text,text,text) to anon,authenticated;

create or replace function public.servicepro_claim_staff_invite(p_company_id uuid,p_role text,p_code text,p_first_name text,p_last_name text,p_job_title text,p_language text) returns void
language sql security invoker set search_path='' as $$ select servicepro_private.claim_staff_invite(p_company_id,p_role,p_code,p_first_name,p_last_name,p_job_title,p_language) $$;
revoke all on function servicepro_private.claim_staff_invite(uuid,text,text,text,text,text,text) from public,anon,authenticated;
grant execute on function servicepro_private.claim_staff_invite(uuid,text,text,text,text,text,text) to authenticated;
revoke all on function public.servicepro_claim_staff_invite(uuid,text,text,text,text,text,text) from public,anon,authenticated;
grant execute on function public.servicepro_claim_staff_invite(uuid,text,text,text,text,text,text) to authenticated;

create or replace function public.servicepro_team_directory() returns jsonb
language sql security invoker set search_path='' as $$ select servicepro_private.team_directory() $$;
revoke all on function servicepro_private.team_directory() from public,anon,authenticated;
grant execute on function servicepro_private.team_directory() to authenticated;
revoke all on function public.servicepro_team_directory() from public,anon,authenticated;
grant execute on function public.servicepro_team_directory() to authenticated;

create or replace function public.servicepro_transition_ticket(p_ticket_id uuid,p_complete boolean,p_description text,p_media text[]) returns public.tickets
language sql security invoker set search_path='' as $$ select servicepro_private.transition_ticket(p_ticket_id,p_complete,p_description,p_media) $$;
revoke all on function servicepro_private.transition_ticket(uuid,boolean,text,text[]) from public,anon,authenticated;
grant execute on function servicepro_private.transition_ticket(uuid,boolean,text,text[]) to authenticated;
revoke all on function public.servicepro_transition_ticket(uuid,boolean,text,text[]) from public,anon,authenticated;
grant execute on function public.servicepro_transition_ticket(uuid,boolean,text,text[]) to authenticated;

revoke all on function servicepro_private.protect_profile_identity() from public,anon,authenticated;
revoke all on function servicepro_private.protect_resident_ticket() from public,anon,authenticated;
commit;
