-- Apply after 20261009122140_guest_staff_access.sql.
-- Shared organization code authorizes FIRST enrollment as director/admin/worker.
-- Existing account role/company cannot be overwritten by a shared code.
-- Personal Supabase password remains separate from the organization code.
begin;
create or replace function servicepro_private.check_company_code(p_company_id uuid,p_code text)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.companies c where c.id=p_company_id and c.is_active and c.join_password=trim(p_code) and length(trim(p_code))>0)
$$;
create or replace function public.servicepro_check_company_code(p_company_id uuid,p_code text)
returns boolean language sql security invoker set search_path='' as $$
 select servicepro_private.check_company_code(p_company_id,p_code)
$$;
revoke all on function servicepro_private.check_company_code(uuid,text) from public,anon,authenticated;
revoke all on function public.servicepro_check_company_code(uuid,text) from public,anon,authenticated;
grant execute on function servicepro_private.check_company_code(uuid,text) to anon,authenticated;
grant execute on function public.servicepro_check_company_code(uuid,text) to anon,authenticated;

create or replace function servicepro_private.join_company_staff(p_company_id uuid,p_role text,p_code text,p_first_name text,p_last_name text,p_job_title text,p_language text)
returns void language plpgsql security definer set search_path='' as $$
declare expected_email text; existing public.profiles;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if p_role is null or p_role not in ('director','admin','worker') then raise exception 'Invalid staff role'; end if;
 if coalesce(trim(p_first_name),'')='' or coalesce(trim(p_last_name),'')='' then raise exception 'Name required'; end if;
 if not servicepro_private.check_company_code(p_company_id,p_code) then raise exception 'Invalid organization code'; end if;
 if p_role='worker' and coalesce(trim(p_job_title),'')='' then raise exception 'Job title required'; end if;
 expected_email := 'staff_'||substr(encode(sha256(convert_to(p_company_id::text||'|'||lower(trim(p_first_name))||'|'||lower(trim(p_last_name)),'UTF8')),'hex'),1,48)||'@servicepro.local';
 if lower(coalesce(auth.jwt()->>'email',''))<>expected_email then raise exception 'Account mismatch'; end if;
 -- Serialize retries for the same auth user. No profile is ever promoted here.
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
 select * into existing from public.profiles where id=auth.uid();
 if found then
  if existing.company_id is distinct from p_company_id or existing.role is distinct from p_role then raise exception 'Account role or organization mismatch'; end if;
  return;
 end if;
 insert into public.profiles(id,company_id,role,first_name,last_name,email,job_title,language)
 values(auth.uid(),p_company_id,p_role,trim(p_first_name),trim(p_last_name),expected_email,trim(coalesce(p_job_title,'')),p_language);
end $$;
create or replace function public.servicepro_join_company_staff(p_company_id uuid,p_role text,p_code text,p_first_name text,p_last_name text,p_job_title text,p_language text)
returns void language sql security invoker set search_path='' as $$
 select servicepro_private.join_company_staff(p_company_id,p_role,p_code,p_first_name,p_last_name,p_job_title,p_language)
$$;
revoke all on function servicepro_private.join_company_staff(uuid,text,text,text,text,text,text) from public,anon,authenticated;
revoke all on function public.servicepro_join_company_staff(uuid,text,text,text,text,text,text) from public,anon,authenticated;
grant execute on function servicepro_private.join_company_staff(uuid,text,text,text,text,text,text) to authenticated;
grant execute on function public.servicepro_join_company_staff(uuid,text,text,text,text,text,text) to authenticated;
commit;
