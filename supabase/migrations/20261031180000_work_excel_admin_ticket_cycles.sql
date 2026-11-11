-- ServicePro: additive ticket numbering cycles + reversible work archive.
-- Apply only AFTER servicepro_schema.sql and WORK_ACTIVITY_ADS_SETUP.sql.
-- Existing tickets, their printed numbers, work records, and media are retained.
begin;

create schema if not exists servicepro_private;

create sequence if not exists public.ticket_reset_cycle_seq;
create table if not exists public.ticket_number_cycles (
  company_id uuid primary key references public.companies(id) on delete cascade,
  cycle_no integer not null check (cycle_no > 0),
  cycle_token bigint not null unique,
  last_number bigint not null default 0 check (last_number >= 0),
  started_at timestamptz not null default now(),
  started_by uuid references public.profiles(id) on delete set null
);
create table if not exists public.ticket_number_cycle_history (
  id bigint generated always as identity primary key,
  company_id uuid not null references public.companies(id) on delete cascade,
  cycle_no integer not null,
  cycle_token bigint not null unique,
  started_at timestamptz not null default now(),
  started_by uuid references public.profiles(id) on delete set null
);
alter table public.ticket_number_cycles enable row level security;
alter table public.ticket_number_cycle_history enable row level security;
revoke all on public.ticket_number_cycles, public.ticket_number_cycle_history
  from public, anon, authenticated;
grant select on public.ticket_number_cycles, public.ticket_number_cycle_history to authenticated;
drop policy if exists "superadmin ticket cycles read" on public.ticket_number_cycles;
create policy "superadmin ticket cycles read" on public.ticket_number_cycles
  for select to authenticated using (public.is_super_admin());
drop policy if exists "superadmin ticket cycle history read" on public.ticket_number_cycle_history;
create policy "superadmin ticket cycle history read" on public.ticket_number_cycle_history
  for select to authenticated using (public.is_super_admin());

-- Same transaction lock is used by both reset and ticket insertion. An in-flight
-- ticket cannot receive the previous numbering scheme after a reset commits.
create or replace function servicepro_private.ticket_number_before_insert()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_token bigint; v_number bigint;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(new.company_id::text, 0));
  update public.ticket_number_cycles
  set last_number = last_number + 1
  where company_id = new.company_id
  returning cycle_token, last_number into v_token, v_number;
  if found then
    new.ticket_number := 'SP-' || to_char(now(), 'YYYY') || '-R'
      || lpad(v_token::text, 6, '0') || '-' || lpad(v_number::text, 6, '0');
  end if;
  return new;
end $$;
drop trigger if exists servicepro_ticket_number_cycle_insert on public.tickets;
create trigger servicepro_ticket_number_cycle_insert
  before insert on public.tickets for each row
  execute function servicepro_private.ticket_number_before_insert();

create or replace function servicepro_private.reset_company_ticket_numbering(p_company_id uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare v_cycle integer; v_token bigint;
begin
  if auth.uid() is null or not public.is_super_admin() then
    raise exception 'super_admin_required';
  end if;
  if not exists(select 1 from public.companies where id = p_company_id) then
    raise exception 'company_not_found';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_company_id::text, 0));
  v_token := nextval('public.ticket_reset_cycle_seq');
  insert into public.ticket_number_cycles(company_id, cycle_no, cycle_token, last_number, started_by)
  values(p_company_id, 1, v_token, 0, auth.uid())
  on conflict(company_id) do update set
    cycle_no = public.ticket_number_cycles.cycle_no + 1,
    cycle_token = excluded.cycle_token,
    last_number = 0,
    started_at = now(),
    started_by = auth.uid()
  returning cycle_no into v_cycle;
  insert into public.ticket_number_cycle_history(company_id,cycle_no,cycle_token,started_by)
  values(p_company_id,v_cycle,v_token,auth.uid());
  return 'SP-' || to_char(now(), 'YYYY') || '-R' || lpad(v_token::text,6,'0') || '-000001';
end $$;
create or replace function public.servicepro_reset_company_ticket_numbering(p_company_id uuid)
returns text language sql security invoker set search_path = '' as $$
  select servicepro_private.reset_company_ticket_numbering(p_company_id)
$$;
revoke all on function servicepro_private.ticket_number_before_insert(),
  servicepro_private.reset_company_ticket_numbering(uuid),
  public.servicepro_reset_company_ticket_numbering(uuid)
  from public, anon, authenticated;
grant execute on function servicepro_private.reset_company_ticket_numbering(uuid),
  public.servicepro_reset_company_ticket_numbering(uuid) to authenticated;

alter table public.work_items
  add column if not exists archived_at timestamptz,
  add column if not exists archived_by uuid references public.profiles(id) on delete set null;
create index if not exists work_items_active_company_idx
  on public.work_items(company_id,created_at desc) where archived_at is null;
drop policy if exists "work items visible to worker and company managers" on public.work_items;
create policy "work items visible to worker and company managers" on public.work_items
  for select to authenticated using (
    public.is_super_admin() or (archived_at is null and (
      (worker_id = (select auth.uid()) and company_id = public.my_company_id())
      or (company_id = public.my_company_id()
          and public.my_role() in ('director','admin'))
    ))
  );

-- Existing SECURITY DEFINER worker RPCs must not modify an archived item
-- even when they know its UUID. Only a super admin may restore/edit it.
create or replace function servicepro_private.work_protect_archived()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if old.archived_at is not null and not public.is_super_admin() then
    raise exception 'work_item_is_archived';
  end if;
  return new;
end $$;
drop trigger if exists servicepro_work_protect_archived on public.work_items;
create trigger servicepro_work_protect_archived
  before update on public.work_items for each row
  execute function servicepro_private.work_protect_archived();
revoke all on function servicepro_private.work_protect_archived()
  from public, anon, authenticated;

alter table public.work_item_events drop constraint if exists work_item_events_action_check;
alter table public.work_item_events add constraint work_item_events_action_check
  check (action in ('assigned','started','submitted','approved','rework','cancelled',
    'edited','archived','restored'));

create or replace function servicepro_private.admin_work_save(
  p_item_id uuid, p_company_id uuid, p_worker_id uuid, p_kind text,
  p_title text, p_description text, p_location text, p_media text[]
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_company uuid; v_kind text; v_item public.work_items%rowtype;
  v_paths text[] := coalesce(p_media, '{}'::text[]);
begin
  if auth.uid() is null or not public.is_super_admin() then raise exception 'super_admin_required'; end if;
  if length(trim(coalesce(p_title,''))) not between 4 and 160
     or length(trim(coalesce(p_description,''))) not between 5 and 4000
     or length(coalesce(p_location,'')) > 500 then raise exception 'invalid_work_fields'; end if;
  if p_item_id is not null then
    select * into v_item from public.work_items where id = p_item_id for update;
    if not found then raise exception 'work_item_not_found'; end if;
    if v_item.archived_at is not null then raise exception 'restore_before_edit'; end if;
    v_company := v_item.company_id; v_kind := v_item.kind;
  else
    v_company := p_company_id; v_kind := p_kind;
    if v_kind not in ('assignment','daily')
       or not exists(select 1 from public.companies where id = v_company)
       then raise exception 'invalid_company_or_work_type'; end if;
  end if;
  if p_worker_id is null or not exists(select 1 from public.profiles
      where id=p_worker_id and company_id=v_company and role='worker')
    then raise exception 'worker_not_in_company'; end if;
  perform servicepro_private.work_validate_media(v_company, auth.uid(), v_paths, false);
  if p_item_id is null then
    if v_kind='daily' and cardinality(v_paths)=0 then raise exception 'report_media_required'; end if;
    insert into public.work_items(company_id,worker_id,created_by,kind,category,
      title,description,location_text,instruction_media,evidence_media,
      report_text,status,work_date)
    values(v_company,p_worker_id,auth.uid(),v_kind,'other',trim(p_title),trim(p_description),
      trim(coalesce(p_location,'')),case when v_kind='assignment' then v_paths else '{}'::text[] end,
      case when v_kind='daily' then v_paths else '{}'::text[] end,
      case when v_kind='daily' then trim(p_description) else '' end,
      case when v_kind='daily' then 'submitted' else 'assigned' end,
      case when v_kind='daily' then (now() at time zone 'Asia/Tashkent')::date else null end)
    returning id into v_id;
    insert into public.work_item_events(item_id,company_id,actor_id,action,note,media_paths)
    values(v_id,v_company,auth.uid(),case when v_kind='daily' then 'submitted' else 'assigned' end,
      'Super admin yaratdi: '||left(trim(p_description),1000),v_paths);
    if v_kind='assignment' then
      insert into public.notifications(profile_id,title,body,notification_type,company_id,sent_by)
      values(p_worker_id,'Yangi ish topshirig‘i',left(trim(p_title),160),
        'work_assigned',v_company,auth.uid());
    else
      insert into public.notifications(profile_id,title,body,notification_type,company_id,sent_by)
      select id,'Yangi kunlik ish hisoboti',left(trim(p_title),160),
        'work_submitted',v_company,auth.uid() from public.profiles
      where company_id=v_company and role in ('director','admin');
    end if;
  else
    update public.work_items set worker_id=p_worker_id, title=trim(p_title),
      description=trim(p_description),location_text=trim(coalesce(p_location,'')),
      instruction_media=case when v_kind='assignment' and cardinality(v_paths)>0
        then instruction_media || v_paths else instruction_media end,
      evidence_media=case when v_kind='daily' and cardinality(v_paths)>0
        then evidence_media || v_paths else evidence_media end,
      report_text=case when v_kind='daily' then trim(p_description) else report_text end,
      updated_at=now()
    where id=p_item_id returning id into v_id;
    insert into public.work_item_events(item_id,company_id,actor_id,action,note,media_paths)
    values(v_id,v_company,auth.uid(),'edited',trim(p_description),v_paths);
  end if;
  return v_id;
end $$;

create or replace function servicepro_private.admin_work_archive(p_item_id uuid,p_archive boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare v_item public.work_items%rowtype;
begin
  if auth.uid() is null or not public.is_super_admin() then raise exception 'super_admin_required'; end if;
  select * into v_item from public.work_items where id=p_item_id for update;
  if not found then raise exception 'work_item_not_found'; end if;
  update public.work_items set archived_at=case when p_archive then now() else null end,
    archived_by=case when p_archive then auth.uid() else null end,
    updated_at=now() where id=p_item_id;
  insert into public.work_item_events(item_id,company_id,actor_id,action,note)
    values(v_item.id,v_item.company_id,auth.uid(),
      case when p_archive then 'archived' else 'restored' end,
      case when p_archive then 'Super admin arxivga o‘tkazdi' else 'Super admin qayta tikladi' end);
end $$;

create or replace function servicepro_private.admin_work_review(
  p_item_id uuid,p_approved boolean,p_note text
) returns void language plpgsql security definer set search_path = '' as $$
declare v_item public.work_items%rowtype;
begin
  if auth.uid() is null or not public.is_super_admin() then raise exception 'super_admin_required'; end if;
  select * into v_item from public.work_items where id=p_item_id for update;
  if not found or v_item.archived_at is not null or v_item.status <> 'submitted'
     then raise exception 'work_item_cannot_be_reviewed'; end if;
  if not p_approved and length(trim(coalesce(p_note,''))) < 4 then
    raise exception 'rework_reason_required'; end if;
  update public.work_items set status=case when p_approved then 'approved' else 'rework' end,
    reviewed_by=auth.uid(),reviewed_at=now(),review_note=trim(coalesce(p_note,'')),updated_at=now()
    where id=p_item_id;
  insert into public.work_item_events(item_id,company_id,actor_id,action,note)
    values(v_item.id,v_item.company_id,auth.uid(),
      case when p_approved then 'approved' else 'rework' end,trim(coalesce(p_note,'')));
  if v_item.worker_id is not null then
    insert into public.notifications(profile_id,title,body,notification_type,company_id,sent_by)
    values(v_item.worker_id,
      case when p_approved then 'Ish hisoboti tasdiqlandi'
        else 'Ish qayta ishlashga qaytarildi' end,
      left(v_item.title||': '||coalesce(p_note,''),300),
      'work_reviewed',v_item.company_id,auth.uid());
  end if;
end $$;

create or replace function public.servicepro_admin_work_save(
  p_item_id uuid,p_company_id uuid,p_worker_id uuid,p_kind text,
  p_title text,p_description text,p_location text,p_media text[]
) returns uuid language sql security invoker set search_path='' as $$
  select servicepro_private.admin_work_save(p_item_id,p_company_id,p_worker_id,p_kind,
    p_title,p_description,p_location,p_media)
$$;
create or replace function public.servicepro_admin_work_archive(p_item_id uuid,p_archive boolean)
returns void language sql security invoker set search_path='' as $$
  select servicepro_private.admin_work_archive(p_item_id,p_archive)
$$;
create or replace function public.servicepro_admin_work_review(
  p_item_id uuid,p_approved boolean,p_note text
) returns void language sql security invoker set search_path='' as $$
  select servicepro_private.admin_work_review(p_item_id,p_approved,p_note)
$$;

revoke all on function
  servicepro_private.admin_work_save(uuid,uuid,uuid,text,text,text,text,text[]),
  servicepro_private.admin_work_archive(uuid,boolean),
  servicepro_private.admin_work_review(uuid,boolean,text),
  public.servicepro_admin_work_save(uuid,uuid,uuid,text,text,text,text,text[]),
  public.servicepro_admin_work_archive(uuid,boolean),
  public.servicepro_admin_work_review(uuid,boolean,text)
  from public, anon, authenticated;
grant execute on function
  servicepro_private.admin_work_save(uuid,uuid,uuid,text,text,text,text,text[]),
  servicepro_private.admin_work_archive(uuid,boolean),
  servicepro_private.admin_work_review(uuid,boolean,text),
  public.servicepro_admin_work_save(uuid,uuid,uuid,text,text,text,text,text[]),
  public.servicepro_admin_work_archive(uuid,boolean),
  public.servicepro_admin_work_review(uuid,boolean,text) to authenticated;

-- Super admin may read and attach work media, but only to an existing company
-- and to their own authenticated upload path.
drop policy if exists "work evidence superadmin read" on storage.objects;
create policy "work evidence superadmin read" on storage.objects
  for select to authenticated using (
    bucket_id='work-evidence' and public.is_super_admin()
  );
drop policy if exists "work evidence superadmin upload" on storage.objects;
create policy "work evidence superadmin upload" on storage.objects
  for insert to authenticated with check (
    bucket_id='work-evidence' and public.is_super_admin()
    and split_part(name,'/',2)=(select auth.uid())::text
    and exists(select 1 from public.companies c
      where c.id::text=split_part(name,'/',1))
  );
drop policy if exists "work evidence worker assigned media" on storage.objects;
create policy "work evidence worker assigned media" on storage.objects
  for select to authenticated using (
    bucket_id='work-evidence' and public.my_role()='worker'
    and exists(select 1 from public.work_items w
      where w.worker_id=(select auth.uid())
        and w.company_id=public.my_company_id()
        and w.archived_at is null
        and (name=any(w.instruction_media) or name=any(w.evidence_media)))
  );

commit;
