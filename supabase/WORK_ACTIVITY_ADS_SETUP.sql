-- ServicePro / Ishchilar vazifalari + kunlik hisobotlari + reklama havolasi.
-- ADDITIVE: old tickets, billing, chats, ads and company profiles are untouched.
-- Run after the existing servicepro migrations; test on a staging database first.

alter table public.notifications add column if not exists action_url text;
alter table public.notifications add column if not exists action_label text not null default 'Batafsil';
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'notifications_ad_action_url_safe') then
    alter table public.notifications add constraint notifications_ad_action_url_safe
      check (action_url is null or
        (length(action_url) <= 2048 and action_url ~* '^https?://[^[:space:]]+$'));
  end if;
end $$;

create table if not exists public.work_items (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  -- A worker leaving the system must not erase already-submitted reports.
  worker_id uuid references public.profiles(id) on delete set null,
  created_by uuid references public.profiles(id) on delete set null,
  kind text not null check (kind in ('assignment','daily')),
  category text not null default 'other',
  title text not null,
  description text not null,
  location_text text not null default '',
  priority text not null default 'normal' check (priority in ('low','normal','high','urgent')),
  due_on date,
  work_date date,
  instruction_media text[] not null default '{}',
  evidence_media text[] not null default '{}',
  report_text text not null default '',
  status text not null check (status in ('assigned','in_progress','submitted','approved','rework','cancelled')),
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  review_note text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint work_title_length check (length(trim(title)) between 4 and 160),
  constraint work_description_length check (length(trim(description)) between 5 and 4000),
  constraint work_worker_proof check (
    status not in ('submitted','approved') or cardinality(evidence_media) > 0
  )
);
create index if not exists work_items_company_recent_idx
  on public.work_items(company_id, created_at desc);
create index if not exists work_items_worker_recent_idx
  on public.work_items(worker_id, created_at desc);
create index if not exists work_items_company_status_idx
  on public.work_items(company_id, status, due_on);

create table if not exists public.work_item_events (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.work_items(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete set null,
  action text not null check (action in
    ('assigned','started','submitted','approved','rework','cancelled')),
  note text not null default '',
  media_paths text[] not null default '{}',
  created_at timestamptz not null default now()
);
create index if not exists work_item_events_item_date_idx
  on public.work_item_events(item_id, created_at desc);

alter table public.work_items enable row level security;
alter table public.work_item_events enable row level security;
revoke all on public.work_items, public.work_item_events
  from public, anon, authenticated;
grant select on public.work_items, public.work_item_events to authenticated;

drop policy if exists "work items visible to worker and company managers"
  on public.work_items;
create policy "work items visible to worker and company managers"
  on public.work_items for select to authenticated using (
    (worker_id = (select auth.uid()) and company_id = public.my_company_id())
    or (company_id = public.my_company_id()
      and public.my_role() in ('director','admin'))
    or public.is_super_admin()
  );
drop policy if exists "work item events follow parent visibility"
  on public.work_item_events;
create policy "work item events follow parent visibility"
  on public.work_item_events for select to authenticated using (
    exists (select 1 from public.work_items w where w.id = item_id)
  );

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('work-evidence','work-evidence',false,83886080,
  array['image/jpeg','image/png','image/webp','image/gif',
        'video/mp4','video/quicktime','video/webm'])
on conflict (id) do nothing;
update storage.buckets
set public=false, file_size_limit=83886080,
  allowed_mime_types=array['image/jpeg','image/png','image/webp','image/gif',
    'video/mp4','video/quicktime','video/webm']
where id='work-evidence';

-- Storage path: COMPANY_UUID / UPLOADER_UUID / UNIQUE_FILE.ext
drop policy if exists "work evidence read company staff" on storage.objects;
create policy "work evidence read company staff" on storage.objects
for select to authenticated using (
  bucket_id = 'work-evidence'
  and split_part(name,'/',1) = public.my_company_id()::text
  and (
    public.my_role() in ('director','admin')
    or (public.my_role() = 'worker' and (
      split_part(name,'/',2) = (select auth.uid())::text
      or exists (select 1 from public.work_items w
        where w.worker_id = (select auth.uid())
          and name = any(w.instruction_media))
    ))
  )
);
drop policy if exists "work evidence upload owner only" on storage.objects;
create policy "work evidence upload owner only" on storage.objects
for insert to authenticated with check (
  bucket_id = 'work-evidence'
  and public.my_role() in ('director','admin','worker')
  and split_part(name,'/',1) = public.my_company_id()::text
  and split_part(name,'/',2) = (select auth.uid())::text
);

-- Security-definer code remains inside the NON-exposed private schema.
-- Every operation checks the authenticated profile and the company boundary.
create or replace function servicepro_private.work_validate_media(
  p_company uuid,p_actor uuid,p_paths text[],p_required boolean
) returns void language plpgsql security definer set search_path='' as $$
declare v_path text;
begin
  if cardinality(coalesce(p_paths,'{}'::text[])) > 8 then
    raise exception 'too_many_media_files';
  end if;
  if p_required and cardinality(coalesce(p_paths,'{}'::text[])) = 0 then
    raise exception 'worker_media_required';
  end if;
  foreach v_path in array coalesce(p_paths,'{}'::text[]) loop
    if v_path is null or left(v_path,length(p_company::text||'/'||p_actor::text||'/'))
       <> p_company::text||'/'||p_actor::text||'/'
       or not exists (select 1 from storage.objects o
         where o.bucket_id='work-evidence' and o.name=v_path) then
      raise exception 'invalid_or_unowned_media';
    end if;
  end loop;
end $$;

create or replace function servicepro_private.work_create_assignment(
  p_worker_id uuid,p_title text,p_description text,p_location text,
  p_category text,p_priority text,p_due_on date,p_media text[]
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_me public.profiles%rowtype; v_id uuid;
begin
  select * into v_me from public.profiles where id=(select auth.uid());
  if not found or v_me.role not in ('director','admin') or v_me.company_id is null
    then raise exception 'manager_required'; end if;
  if not exists(select 1 from public.profiles where id=p_worker_id
    and company_id=v_me.company_id and role='worker')
    then raise exception 'worker_not_in_company'; end if;
  if length(trim(coalesce(p_title,''))) not between 4 and 160
    or length(trim(coalesce(p_description,''))) not between 5 and 4000
    then raise exception 'invalid_task_fields'; end if;
  if p_priority not in ('low','normal','high','urgent')
    then raise exception 'invalid_priority'; end if;
  perform servicepro_private.work_validate_media(
    v_me.company_id,v_me.id,p_media,false);
  insert into public.work_items(company_id,worker_id,created_by,kind,
    category,title,description,location_text,priority,due_on,instruction_media,status)
  values(v_me.company_id,p_worker_id,v_me.id,'assignment',
    coalesce(nullif(trim(p_category),''),'other'),trim(p_title),trim(p_description),
    trim(coalesce(p_location,'')),p_priority,p_due_on,coalesce(p_media,'{}'),'assigned')
  returning id into v_id;
  insert into public.work_item_events(item_id,company_id,actor_id,action,note,media_paths)
  values(v_id,v_me.company_id,v_me.id,'assigned',trim(p_description),coalesce(p_media,'{}'));
  insert into public.notifications(profile_id,title,body,notification_type,company_id,sent_by)
  values(p_worker_id,'Yangi ish topshirig‘i',left(trim(p_title),160),
    'work_assigned',v_me.company_id,v_me.id);
  return v_id;
end $$;

create or replace function servicepro_private.work_create_daily(
  p_title text,p_description text,p_location text,p_category text,
  p_work_date date,p_media text[]
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_me public.profiles%rowtype; v_id uuid; v_today date;
begin
  select * into v_me from public.profiles where id=(select auth.uid());
  if not found or v_me.role <> 'worker' or v_me.company_id is null
    then raise exception 'worker_required'; end if;
  v_today := (now() at time zone 'Asia/Tashkent')::date;
  if p_work_date is null or p_work_date > v_today
    or p_work_date < v_today-30 then raise exception 'invalid_work_date'; end if;
  if length(trim(coalesce(p_title,''))) not between 4 and 160
    or length(trim(coalesce(p_description,''))) not between 5 and 4000
    then raise exception 'invalid_report_fields'; end if;
  perform servicepro_private.work_validate_media(
    v_me.company_id,v_me.id,p_media,true);
  insert into public.work_items(company_id,worker_id,created_by,kind,
    category,title,description,location_text,work_date,evidence_media,
    report_text,status)
  values(v_me.company_id,v_me.id,v_me.id,'daily',
    coalesce(nullif(trim(p_category),''),'other'),trim(p_title),trim(p_description),
    trim(coalesce(p_location,'')),p_work_date,p_media,trim(p_description),'submitted')
  returning id into v_id;
  insert into public.work_item_events(item_id,company_id,actor_id,action,note,media_paths)
  values(v_id,v_me.company_id,v_me.id,'submitted',trim(p_description),p_media);
  insert into public.notifications(profile_id,title,body,notification_type,company_id,sent_by)
  select id,'Yangi kunlik ish hisoboti',left(trim(p_title),160),
    'work_submitted',v_me.company_id,v_me.id
  from public.profiles where company_id=v_me.company_id and role in ('director','admin');
  return v_id;
end $$;

create or replace function servicepro_private.work_start_assignment(p_item_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare v_item public.work_items%rowtype;
begin
  select * into v_item from public.work_items where id=p_item_id for update;
  if not found or v_item.kind <> 'assignment'
    or v_item.worker_id <> (select auth.uid())
    or v_item.company_id is distinct from public.my_company_id()
    or v_item.status not in ('assigned','rework') then
    raise exception 'task_cannot_start'; end if;
  update public.work_items set status='in_progress',updated_at=now()
  where id=p_item_id;
  insert into public.work_item_events(item_id,company_id,actor_id,action)
  values(v_item.id,v_item.company_id,(select auth.uid()),'started');
end $$;

create or replace function servicepro_private.work_submit_assignment(
  p_item_id uuid,p_report text,p_work_date date,p_media text[]
) returns void language plpgsql security definer set search_path='' as $$
declare v_item public.work_items%rowtype; v_today date;
begin
  select * into v_item from public.work_items where id=p_item_id for update;
  if not found or v_item.kind <> 'assignment'
    or v_item.worker_id <> (select auth.uid())
    or v_item.company_id is distinct from public.my_company_id()
    or v_item.status not in ('assigned','in_progress','rework') then
    raise exception 'task_cannot_submit'; end if;
  if length(trim(coalesce(p_report,''))) < 5 then
    raise exception 'report_description_required'; end if;
  v_today := (now() at time zone 'Asia/Tashkent')::date;
  if p_work_date is null or p_work_date > v_today
    or p_work_date < v_today-30 then raise exception 'invalid_work_date'; end if;
  perform servicepro_private.work_validate_media(
    v_item.company_id,(select auth.uid()),p_media,true);
  update public.work_items set status='submitted',work_date=p_work_date,
    report_text=trim(p_report),evidence_media=p_media,
    reviewed_by=null,reviewed_at=null,review_note='',updated_at=now()
  where id=p_item_id;
  insert into public.work_item_events(item_id,company_id,actor_id,action,note,media_paths)
  values(v_item.id,v_item.company_id,(select auth.uid()),'submitted',trim(p_report),p_media);
  insert into public.notifications(profile_id,title,body,notification_type,company_id,sent_by)
  select id,'Topshiriq bajarildi',left(v_item.title,160),
    'work_submitted',v_item.company_id,(select auth.uid())
  from public.profiles where company_id=v_item.company_id and role in ('director','admin');
end $$;

create or replace function servicepro_private.work_resubmit_daily(
  p_item_id uuid,p_report text,p_work_date date,p_media text[]
) returns void language plpgsql security definer set search_path='' as $$
declare v_item public.work_items%rowtype; v_today date;
begin
  select * into v_item from public.work_items where id=p_item_id for update;
  if not found or v_item.kind <> 'daily'
    or v_item.worker_id <> (select auth.uid())
    or v_item.company_id is distinct from public.my_company_id()
    or v_item.status <> 'rework'
    then raise exception 'daily_report_cannot_resubmit'; end if;
  if length(trim(coalesce(p_report,''))) < 5 then
    raise exception 'report_description_required'; end if;
  v_today := (now() at time zone 'Asia/Tashkent')::date;
  if p_work_date is null or p_work_date > v_today or p_work_date < v_today-30
    then raise exception 'invalid_work_date'; end if;
  perform servicepro_private.work_validate_media(
    v_item.company_id,(select auth.uid()),p_media,true);
  update public.work_items set status='submitted',
    report_text=trim(p_report),evidence_media=p_media,work_date=p_work_date,
    reviewed_by=null,reviewed_at=null,review_note='',updated_at=now()
  where id=p_item_id;
  insert into public.work_item_events(item_id,company_id,actor_id,action,note,media_paths)
  values(v_item.id,v_item.company_id,(select auth.uid()),'submitted',trim(p_report),p_media);
  insert into public.notifications(profile_id,title,body,notification_type,company_id,sent_by)
  select id,'Kunlik hisobot qayta yuborildi',left(v_item.title,160),
    'work_submitted',v_item.company_id,(select auth.uid())
  from public.profiles where company_id=v_item.company_id and role in ('director','admin');
end $$;

create or replace function servicepro_private.work_review_item(
  p_item_id uuid,p_approved boolean,p_note text
) returns void language plpgsql security definer set search_path='' as $$
declare v_item public.work_items%rowtype; v_me public.profiles%rowtype;
begin
  select * into v_me from public.profiles where id=(select auth.uid());
  select * into v_item from public.work_items where id=p_item_id for update;
  if not found or v_item.company_id is distinct from v_me.company_id
    or v_me.role not in ('director','admin') or v_item.status <> 'submitted'
    then raise exception 'review_not_permitted'; end if;
  if not coalesce(p_approved,false) and length(trim(coalesce(p_note,''))) < 4
    then raise exception 'rework_reason_required'; end if;
  update public.work_items
  set status=case when p_approved then 'approved' else 'rework' end,
    reviewed_by=v_me.id,reviewed_at=now(),
    review_note=trim(coalesce(p_note,'')),updated_at=now()
  where id=p_item_id;
  insert into public.work_item_events(item_id,company_id,actor_id,action,note)
  values(v_item.id,v_item.company_id,v_me.id,
    case when p_approved then 'approved' else 'rework' end,trim(coalesce(p_note,'')));
  insert into public.notifications(profile_id,title,body,notification_type,company_id,sent_by)
  values(v_item.worker_id,
    case when p_approved then 'Ish hisoboti tasdiqlandi' else 'Ish qayta ishlashga qaytarildi' end,
    left(v_item.title||': '||coalesce(p_note,''),300),
    'work_reviewed',v_item.company_id,v_me.id);
end $$;

create or replace function servicepro_private.work_cancel_assignment(
  p_item_id uuid,p_reason text
) returns void language plpgsql security definer set search_path='' as $$
declare v_item public.work_items%rowtype; v_me public.profiles%rowtype;
begin
  select * into v_me from public.profiles where id=(select auth.uid());
  select * into v_item from public.work_items where id=p_item_id for update;
  if not found or v_item.company_id is distinct from v_me.company_id
    or v_me.role not in ('director','admin') or v_item.kind <> 'assignment'
    or v_item.status not in ('assigned','in_progress','rework')
    then raise exception 'cancel_not_permitted'; end if;
  update public.work_items set status='cancelled',updated_at=now()
  where id=p_item_id;
  insert into public.work_item_events(item_id,company_id,actor_id,action,note)
  values(v_item.id,v_item.company_id,v_me.id,'cancelled',trim(coalesce(p_reason,'')));
  insert into public.notifications(profile_id,title,body,notification_type,company_id,sent_by)
  values(v_item.worker_id,'Topshiriq bekor qilindi',
    left(v_item.title,160),'work_cancelled',v_item.company_id,v_me.id);
end $$;

-- Public invoker wrappers; private privileged functions are not Data API endpoints.
create or replace function public.work_create_assignment(
  p_worker_id uuid,p_title text,p_description text,p_location text,
  p_category text,p_priority text,p_due_on date,p_media text[]
) returns uuid language sql security invoker set search_path='' as $$
  select servicepro_private.work_create_assignment(
    p_worker_id,p_title,p_description,p_location,
    p_category,p_priority,p_due_on,p_media)
$$;
create or replace function public.work_create_daily(
  p_title text,p_description text,p_location text,p_category text,
  p_work_date date,p_media text[]
) returns uuid language sql security invoker set search_path='' as $$
  select servicepro_private.work_create_daily(
    p_title,p_description,p_location,p_category,p_work_date,p_media)
$$;
create or replace function public.work_start_assignment(p_item_id uuid)
returns void language sql security invoker set search_path='' as $$
  select servicepro_private.work_start_assignment(p_item_id)
$$;
create or replace function public.work_submit_assignment(
  p_item_id uuid,p_report text,p_work_date date,p_media text[]
) returns void language sql security invoker set search_path='' as $$
  select servicepro_private.work_submit_assignment(
    p_item_id,p_report,p_work_date,p_media)
$$;
create or replace function public.work_resubmit_daily(
  p_item_id uuid,p_report text,p_work_date date,p_media text[]
) returns void language sql security invoker set search_path='' as $$
  select servicepro_private.work_resubmit_daily(
    p_item_id,p_report,p_work_date,p_media)
$$;
create or replace function public.work_review_item(
  p_item_id uuid,p_approved boolean,p_note text
) returns void language sql security invoker set search_path='' as $$
  select servicepro_private.work_review_item(p_item_id,p_approved,p_note)
$$;
create or replace function public.work_cancel_assignment(
  p_item_id uuid,p_reason text
) returns void language sql security invoker set search_path='' as $$
  select servicepro_private.work_cancel_assignment(p_item_id,p_reason)
$$;

revoke all on function
  servicepro_private.work_validate_media(uuid,uuid,text[],boolean),
  servicepro_private.work_create_assignment(uuid,text,text,text,text,text,date,text[]),
  servicepro_private.work_create_daily(text,text,text,text,date,text[]),
  servicepro_private.work_start_assignment(uuid),
  servicepro_private.work_submit_assignment(uuid,text,date,text[]),
  servicepro_private.work_resubmit_daily(uuid,text,date,text[]),
  servicepro_private.work_review_item(uuid,boolean,text),
  servicepro_private.work_cancel_assignment(uuid,text)
  from public,anon,authenticated;
grant execute on function
  servicepro_private.work_create_assignment(uuid,text,text,text,text,text,date,text[]),
  servicepro_private.work_create_daily(text,text,text,text,date,text[]),
  servicepro_private.work_start_assignment(uuid),
  servicepro_private.work_submit_assignment(uuid,text,date,text[]),
  servicepro_private.work_resubmit_daily(uuid,text,date,text[]),
  servicepro_private.work_review_item(uuid,boolean,text),
  servicepro_private.work_cancel_assignment(uuid,text)
  to authenticated;
revoke all on function
  public.work_create_assignment(uuid,text,text,text,text,text,date,text[]),
  public.work_create_daily(text,text,text,text,date,text[]),
  public.work_start_assignment(uuid),
  public.work_submit_assignment(uuid,text,date,text[]),
  public.work_resubmit_daily(uuid,text,date,text[]),
  public.work_review_item(uuid,boolean,text),
  public.work_cancel_assignment(uuid,text)
  from public,anon,authenticated;
grant execute on function
  public.work_create_assignment(uuid,text,text,text,text,text,date,text[]),
  public.work_create_daily(text,text,text,text,date,text[]),
  public.work_start_assignment(uuid),
  public.work_submit_assignment(uuid,text,date,text[]),
  public.work_resubmit_daily(uuid,text,date,text[]),
  public.work_review_item(uuid,boolean,text),
  public.work_cancel_assignment(uuid,text)
  to authenticated;
