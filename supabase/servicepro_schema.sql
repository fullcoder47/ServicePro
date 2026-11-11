-- ServicePro Supabase backend schema
-- 1) Supabase Dashboard -> Auth -> Providers -> Email: test payti Confirm emailni OFF qiling.
-- 2) Auth -> Providers -> Anonymous Sign-ins: ON qiling.
-- 3) Storage -> bucket: ticket-files, Public bucket ON.
-- 4) SQL Editorda shu faylni to'liq run qiling.

create extension if not exists pgcrypto;

create table if not exists public.companies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  join_password text not null unique,
  director_id uuid not null references auth.users(id) on delete cascade,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  company_id uuid references public.companies(id) on delete cascade,
  role text not null check (role in ('super_admin','director','admin','user')),
  first_name text not null default '',
  last_name text not null default '',
  phone text not null default '',
  email text not null default '',
  avatar_url text,
  language text not null default 'uz' check (language in ('uz','ru','en')),
  theme_mode text not null default 'system' check (theme_mode in ('light','dark','system')),
  created_at timestamptz not null default now()
);

create table if not exists public.buildings (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  street text not null,
  house_number text not null,
  latitude double precision not null default 0,
  longitude double precision not null default 0,
  created_at timestamptz not null default now()
);

create sequence if not exists public.ticket_number_seq start 1;

create or replace function public.next_ticket_number()
returns text
language sql
security definer
set search_path = public
as $$
  select 'SP-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('public.ticket_number_seq')::text, 6, '0');
$$;

grant execute on function public.next_ticket_number() to authenticated;

create table if not exists public.tickets (
  id uuid primary key default gen_random_uuid(),
  ticket_number text not null unique,
  company_id uuid not null references public.companies(id) on delete cascade,
  created_by uuid not null references public.profiles(id) on delete cascade,
  building_id uuid references public.buildings(id) on delete restrict,
  address_text text not null default '',
  apartment_number text not null,
  description text not null,
  attachments text[] not null default '{}',
  status text not null default 'new' check (status in ('new','in_progress','completed','closed')),
  accepted_by uuid references public.profiles(id),
  accepted_at timestamptz,
  completed_by uuid references public.profiles(id),
  completed_at timestamptz,
  completion_description text,
  completion_attachments text[] not null default '{}',
  created_at timestamptz not null default now()
);


-- Existing project migration: manual address field and nullable building_id
alter table public.tickets add column if not exists address_text text not null default '';
alter table public.tickets alter column building_id drop not null;

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid references public.profiles(id) on delete cascade,
  ticket_id uuid references public.tickets(id) on delete cascade,
  title text not null,
  body text not null,
  notification_type text not null default 'system',
  sent_by uuid references public.profiles(id) on delete set null,
  company_id uuid references public.companies(id) on delete cascade,
  media_urls text[] not null default '{}',
  media_types text[] not null default '{}',
  ad_group_id text,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

-- Existing project migrations: profile avatars and advertisement media notifications
alter table public.profiles add column if not exists avatar_url text;
alter table public.notifications add column if not exists notification_type text not null default 'system';
alter table public.notifications add column if not exists sent_by uuid references public.profiles(id) on delete set null;
alter table public.notifications add column if not exists company_id uuid references public.companies(id) on delete cascade;
alter table public.notifications add column if not exists media_urls text[] not null default '{}';
alter table public.notifications add column if not exists media_types text[] not null default '{}';
alter table public.notifications add column if not exists ad_group_id text;
alter table public.notifications alter column profile_id drop not null;
alter table public.notifications add column if not exists audience text not null default 'direct';

create or replace function public.is_super_admin()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists(select 1 from public.profiles p where p.id = auth.uid() and p.role = 'super_admin');
$$;

create or replace function public.my_company_id()
returns uuid
language sql
security definer
set search_path = public
as $$
  select p.company_id from public.profiles p where p.id = auth.uid();
$$;

create or replace function public.my_role()
returns text
language sql
security definer
set search_path = public
as $$
  select p.role from public.profiles p where p.id = auth.uid();
$$;

create or replace function public.find_company_by_join_password(p_join_password text)
returns table(id uuid, name text)
language sql
security definer
set search_path = public
as $$
  select c.id, c.name from public.companies c where c.join_password = p_join_password and c.is_active = true limit 1;
$$;


-- Ticket yaratishni ishonchli qilish uchun RPC.
-- Flutter create flow shu function orqali ishlaydi: ticket raqam serverda beriladi,
-- created_by auth.uid() bo‘ladi, company access tekshiriladi.
create or replace function public.create_service_ticket(
  p_company_id uuid,
  p_address_text text,
  p_apartment_number text,
  p_description text
)
returns public.tickets
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_ticket public.tickets%rowtype;
begin
  select * into v_profile from public.profiles where id = auth.uid();
  if v_profile.id is null then
    raise exception 'profile_not_found';
  end if;

  if coalesce(trim(p_address_text), '') = '' then
    raise exception 'address_required';
  end if;
  if coalesce(trim(p_apartment_number), '') = '' then
    raise exception 'apartment_required';
  end if;
  if coalesce(trim(p_description), '') = '' then
    raise exception 'description_required';
  end if;

  if v_profile.role <> 'super_admin' and v_profile.company_id <> p_company_id then
    raise exception 'company_access_denied';
  end if;

  insert into public.tickets(
    ticket_number,
    company_id,
    created_by,
    address_text,
    apartment_number,
    description,
    status
  ) values (
    public.next_ticket_number(),
    p_company_id,
    auth.uid(),
    trim(p_address_text),
    trim(p_apartment_number),
    trim(p_description),
    'new'
  ) returning * into v_ticket;

  return v_ticket;
end;
$$;

grant execute on function public.create_service_ticket(uuid, text, text, text) to authenticated;

-- Ticket creator media uploaddan keyin request attachmentsni xavfsiz yozish uchun.
-- RLS update policy userga attachments yozishga ruxsat bermasa ham, bu RPC ticket egasini tekshiradi.
create or replace function public.set_ticket_request_attachments(
  p_ticket_id uuid,
  p_attachments text[]
)
returns public.tickets
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ticket public.tickets%rowtype;
begin
  select * into v_ticket from public.tickets where id = p_ticket_id;
  if v_ticket.id is null then
    raise exception 'ticket_not_found';
  end if;

  if not public.is_super_admin()
     and v_ticket.created_by <> auth.uid()
     and not (v_ticket.company_id = public.my_company_id() and public.my_role() in ('director','admin')) then
    raise exception 'ticket_access_denied';
  end if;

  update public.tickets
  set attachments = coalesce(p_attachments, '{}')
  where id = p_ticket_id
  returning * into v_ticket;

  return v_ticket;
end;
$$;

grant execute on function public.set_ticket_request_attachments(uuid, text[]) to authenticated;


alter table public.companies enable row level security;
alter table public.profiles enable row level security;
alter table public.buildings enable row level security;
alter table public.tickets enable row level security;
alter table public.notifications enable row level security;


-- Policy re-run safety
drop policy if exists "companies select own or super" on public.companies;
drop policy if exists "companies insert director" on public.companies;
drop policy if exists "companies update super or director" on public.companies;
drop policy if exists "companies delete super" on public.companies;
drop policy if exists "profiles select own company or super" on public.profiles;
drop policy if exists "profiles insert self" on public.profiles;
drop policy if exists "profiles update self or super" on public.profiles;
drop policy if exists "profiles delete super" on public.profiles;
drop policy if exists "buildings select company or super" on public.buildings;
drop policy if exists "buildings insert company managers" on public.buildings;
drop policy if exists "buildings update company managers" on public.buildings;
drop policy if exists "buildings delete super" on public.buildings;
drop policy if exists "tickets select visible" on public.tickets;
drop policy if exists "tickets insert self company" on public.tickets;
drop policy if exists "tickets update company managers or owner close" on public.tickets;
drop policy if exists "tickets delete super" on public.tickets;
drop policy if exists "notifications select self" on public.notifications;
drop policy if exists "notifications insert company" on public.notifications;
drop policy if exists "notifications update self" on public.notifications;
drop policy if exists "notifications select self sent or super" on public.notifications;
drop policy if exists "notifications update self sent or super" on public.notifications;
drop policy if exists "notifications delete sent or super" on public.notifications;

-- Companies
create policy "companies select own or super" on public.companies for select to authenticated
using (public.is_super_admin() or id = public.my_company_id() or director_id = auth.uid());
create policy "companies insert director" on public.companies for insert to authenticated
with check (director_id = auth.uid());
create policy "companies update super or director" on public.companies for update to authenticated
using (public.is_super_admin() or director_id = auth.uid()) with check (public.is_super_admin() or director_id = auth.uid());
create policy "companies delete super" on public.companies for delete to authenticated
using (public.is_super_admin());

-- Profiles
create policy "profiles select own company or super" on public.profiles for select to authenticated
using (public.is_super_admin() or id = auth.uid() or company_id = public.my_company_id());
create policy "profiles insert self" on public.profiles for insert to authenticated
with check (id = auth.uid());
create policy "profiles update self or super" on public.profiles for update to authenticated
using (id = auth.uid() or public.is_super_admin()) with check (id = auth.uid() or public.is_super_admin());
create policy "profiles delete super" on public.profiles for delete to authenticated
using (public.is_super_admin());

-- Buildings
create policy "buildings select company or super" on public.buildings for select to authenticated
using (public.is_super_admin() or company_id = public.my_company_id());
create policy "buildings insert company managers" on public.buildings for insert to authenticated
with check (public.is_super_admin() or company_id = public.my_company_id());
create policy "buildings update company managers" on public.buildings for update to authenticated
using (public.is_super_admin() or company_id = public.my_company_id()) with check (public.is_super_admin() or company_id = public.my_company_id());
create policy "buildings delete super" on public.buildings for delete to authenticated
using (public.is_super_admin());

-- Tickets
create policy "tickets select visible" on public.tickets for select to authenticated
using (public.is_super_admin() or company_id = public.my_company_id() or created_by = auth.uid());
create policy "tickets insert self company" on public.tickets for insert to authenticated
with check (created_by = auth.uid() and (public.is_super_admin() or company_id = public.my_company_id()));
create policy "tickets update company managers or owner close" on public.tickets for update to authenticated
using (
  public.is_super_admin()
  or (company_id = public.my_company_id() and public.my_role() in ('director','admin'))
  or (created_by = auth.uid() and status in ('new','completed'))
)
with check (
  public.is_super_admin()
  or (company_id = public.my_company_id() and public.my_role() in ('director','admin'))
  or (created_by = auth.uid())
);
create policy "tickets delete super" on public.tickets for delete to authenticated
using (public.is_super_admin());

-- Notifications
create policy "notifications select self sent or super" on public.notifications for select to authenticated
using (
  public.is_super_admin()
  or profile_id = auth.uid()
  or sent_by = auth.uid()
  or (
    notification_type = 'advertisement'
    and profile_id is null
    and audience <> 'user'
    and (company_id is null or company_id = public.my_company_id())
  )
);
create policy "notifications insert company" on public.notifications for insert to authenticated
with check (
  public.is_super_admin()
  or exists(select 1 from public.profiles p where p.id = profile_id and (p.company_id = public.my_company_id() or p.id = auth.uid()))
  or (
    notification_type = 'advertisement'
    and profile_id is null
    and public.my_role() in ('director','admin')
    and company_id = public.my_company_id()
  )
);
create policy "notifications update self sent or super" on public.notifications for update to authenticated
using (profile_id = auth.uid() or sent_by = auth.uid() or public.is_super_admin())
with check (profile_id = auth.uid() or sent_by = auth.uid() or public.is_super_admin());
create policy "notifications delete sent or super" on public.notifications for delete to authenticated
using (sent_by = auth.uid() or public.is_super_admin());

-- Realtime uchun
do $$
begin
  begin
    alter publication supabase_realtime add table public.tickets;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.notifications;
  exception when duplicate_object then null;
  end;
end $$;

-- Super admin userini yaratgandan keyin bir marta shu qatorni o'zingiz user id bilan ishlatasiz:
-- insert into public.profiles(id, role, first_name, last_name, phone, email)
-- values ('AUTH_USER_ID_HERE', 'super_admin', 'Fullcoder', 'Admin', '+998 90 000 00 00', 'fullcoder47@gmail.com')
-- on conflict (id) do update set role='super_admin', email='fullcoder47@gmail.com';


-- Storage policies for ticket-files bucket. Bucketni Supabase Storage bo‘limida public qilib yarating.
drop policy if exists "ticket files select" on storage.objects;
drop policy if exists "ticket files insert" on storage.objects;
drop policy if exists "ticket files update" on storage.objects;
drop policy if exists "ticket files delete super" on storage.objects;

create policy "ticket files select" on storage.objects for select to authenticated
using (bucket_id = 'ticket-files');

create policy "ticket files insert" on storage.objects for insert to authenticated
with check (bucket_id = 'ticket-files');

create policy "ticket files update" on storage.objects for update to authenticated
using (bucket_id = 'ticket-files')
with check (bucket_id = 'ticket-files');

create policy "ticket files delete super" on storage.objects for delete to authenticated
using (bucket_id = 'ticket-files' and public.is_super_admin());

-- =========================
-- Chat module: group/direct realtime chat
-- =========================
create table if not exists public.chat_rooms (
  id uuid primary key default gen_random_uuid(),
  company_id uuid references public.companies(id) on delete cascade,
  type text not null check (type in ('group','direct')),
  title text not null default '',
  direct_key text unique,
  created_by uuid references public.profiles(id) on delete set null,
  last_message text,
  last_message_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

alter table public.chat_rooms add column if not exists direct_key text unique;
alter table public.chat_rooms add column if not exists last_message text;
alter table public.chat_rooms add column if not exists last_message_at timestamptz not null default now();
alter table public.chat_rooms add column if not exists avatar_url text;

create table if not exists public.chat_room_members (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.chat_rooms(id) on delete cascade,
  profile_id uuid references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique(room_id, profile_id)
);

create table if not exists public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.chat_rooms(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  text text not null default '',
  attachments text[] not null default '{}',
  reply_to_message_id uuid references public.chat_messages(id) on delete set null,
  is_edited boolean not null default false,
  is_deleted boolean not null default false,
  deleted_text text,
  deleted_attachments text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz
);

alter table public.chat_rooms add column if not exists pinned_message_id uuid references public.chat_messages(id) on delete set null;
alter table public.chat_messages add column if not exists deleted_text text;
alter table public.chat_messages add column if not exists deleted_attachments text[] not null default '{}';

create or replace function public.chat_can_access_room(p_room_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists(
    select 1
    from public.chat_rooms r
    left join public.chat_room_members m on m.room_id = r.id and m.profile_id = auth.uid()
    where r.id = p_room_id
      and (
        public.is_super_admin()
        or m.profile_id is not null
        or (r.type = 'group' and r.company_id = public.my_company_id())
      )
  );
$$;

grant execute on function public.chat_can_access_room(uuid) to authenticated;

create or replace function public.chat_can_manage_room(p_room_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists(
    select 1
    from public.chat_rooms r
    join public.profiles p on p.id = auth.uid()
    where r.id = p_room_id
      and (
        public.is_super_admin()
        or (
          r.company_id = p.company_id
          and p.role in ('director','admin')
        )
      )
  );
$$;

grant execute on function public.chat_can_manage_room(uuid) to authenticated;

drop policy if exists "chat rooms update visible" on public.chat_rooms;
drop policy if exists "chat rooms update managers" on public.chat_rooms;
drop policy if exists "chat rooms update managers" on public.chat_rooms;

create policy "chat rooms update managers" on public.chat_rooms for update to authenticated
using (public.chat_can_manage_room(id))
with check (public.chat_can_manage_room(id));


create or replace function public.chat_ensure_group_room()
returns public.chat_rooms
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_room public.chat_rooms%rowtype;
begin
  select * into v_profile from public.profiles where id = auth.uid();
  if v_profile.id is null then
    raise exception 'chat_profile_not_found';
  end if;
  if v_profile.company_id is null then
    raise exception 'chat_company_not_found';
  end if;

  select * into v_room
  from public.chat_rooms
  where company_id = v_profile.company_id and type = 'group'
  order by created_at
  limit 1;

  if v_room.id is null then
    insert into public.chat_rooms(company_id, type, title, created_by, last_message, last_message_at)
    values (v_profile.company_id, 'group', 'Umumiy chat', auth.uid(), 'Umumiy chat yaratildi', now())
    returning * into v_room;
  end if;

  insert into public.chat_room_members(room_id, profile_id)
  values (v_room.id, auth.uid())
  on conflict(room_id, profile_id) do nothing;

  return v_room;
end;
$$;

grant execute on function public.chat_ensure_group_room() to authenticated;

create or replace function public.chat_get_or_create_direct_room(p_other_profile_id uuid)
returns public.chat_rooms
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me public.profiles%rowtype;
  v_other public.profiles%rowtype;
  v_room public.chat_rooms%rowtype;
  v_company uuid;
  v_key text;
begin
  select * into v_me from public.profiles where id = auth.uid();
  select * into v_other from public.profiles where id = p_other_profile_id;

  if v_me.id is null or v_other.id is null then
    raise exception 'chat_profile_not_found';
  end if;
  if v_me.id = v_other.id then
    raise exception 'chat_self_direct_not_allowed';
  end if;
  if not public.is_super_admin() and v_me.company_id <> v_other.company_id then
    raise exception 'chat_company_access_denied';
  end if;

  v_company := coalesce(v_me.company_id, v_other.company_id);
  v_key := least(v_me.id::text, v_other.id::text) || '_' || greatest(v_me.id::text, v_other.id::text);

  select * into v_room from public.chat_rooms where direct_key = v_key limit 1;

  if v_room.id is null then
    insert into public.chat_rooms(company_id, type, title, direct_key, created_by, last_message, last_message_at)
    values (
      v_company,
      'direct',
      trim(coalesce(v_me.first_name,'') || ' ' || coalesce(v_me.last_name,'')) || ' ↔ ' || trim(coalesce(v_other.first_name,'') || ' ' || coalesce(v_other.last_name,'')),
      v_key,
      auth.uid(),
      'Shaxsiy chat yaratildi',
      now()
    ) returning * into v_room;
  end if;

  insert into public.chat_room_members(room_id, profile_id) values (v_room.id, v_me.id) on conflict(room_id, profile_id) do nothing;
  insert into public.chat_room_members(room_id, profile_id) values (v_room.id, v_other.id) on conflict(room_id, profile_id) do nothing;

  return v_room;
end;
$$;

grant execute on function public.chat_get_or_create_direct_room(uuid) to authenticated;

create or replace function public.chat_send_message(
  p_room_id uuid,
  p_text text,
  p_attachments text[] default '{}',
  p_reply_to_message_id uuid default null
)
returns public.chat_messages
language plpgsql
security definer
set search_path = public
as $$
declare
  v_message public.chat_messages%rowtype;
  v_preview text;
begin
  if not public.chat_can_access_room(p_room_id) then
    raise exception 'chat_access_denied';
  end if;

  if coalesce(trim(p_text), '') = '' and coalesce(array_length(p_attachments, 1), 0) = 0 then
    raise exception 'chat_message_empty';
  end if;

  if p_reply_to_message_id is not null and not exists(select 1 from public.chat_messages where id = p_reply_to_message_id and room_id = p_room_id) then
    raise exception 'chat_reply_not_found';
  end if;

  insert into public.chat_messages(room_id, sender_id, text, attachments, reply_to_message_id)
  values (p_room_id, auth.uid(), trim(coalesce(p_text, '')), coalesce(p_attachments, '{}'), p_reply_to_message_id)
  returning * into v_message;

  v_preview := case
    when trim(coalesce(p_text, '')) <> '' then trim(p_text)
    when coalesce(array_length(p_attachments, 1), 0) > 0 then 'Fayl yuborildi'
    else 'Yangi xabar'
  end;

  update public.chat_rooms
  set last_message = v_preview,
      last_message_at = now()
  where id = p_room_id;

  return v_message;
end;
$$;

grant execute on function public.chat_send_message(uuid, text, text[], uuid) to authenticated;

create or replace function public.chat_edit_message(p_message_id uuid, p_text text)
returns public.chat_messages
language plpgsql
security definer
set search_path = public
as $$
declare
  v_message public.chat_messages%rowtype;
begin
  select * into v_message from public.chat_messages where id = p_message_id;
  if v_message.id is null then
    raise exception 'chat_message_not_found';
  end if;
  if v_message.sender_id <> auth.uid() and not public.is_super_admin() then
    raise exception 'chat_edit_denied';
  end if;
  if coalesce(trim(p_text), '') = '' then
    raise exception 'chat_message_empty';
  end if;

  update public.chat_messages
  set text = trim(p_text), is_edited = true, updated_at = now()
  where id = p_message_id
  returning * into v_message;

  update public.chat_rooms
  set last_message = trim(p_text), last_message_at = now()
  where id = v_message.room_id;

  return v_message;
end;
$$;

grant execute on function public.chat_edit_message(uuid, text) to authenticated;

create or replace function public.chat_delete_message(p_message_id uuid)
returns public.chat_messages
language plpgsql
security definer
set search_path = public
as $$
declare
  v_message public.chat_messages%rowtype;
begin
  select * into v_message from public.chat_messages where id = p_message_id;
  if v_message.id is null then
    raise exception 'chat_message_not_found';
  end if;
  if v_message.sender_id <> auth.uid() and not public.is_super_admin() then
    raise exception 'chat_delete_denied';
  end if;

  update public.chat_messages
  set deleted_text = text,
      deleted_attachments = attachments,
      text = '',
      attachments = '{}',
      is_deleted = true,
      updated_at = now()
  where id = p_message_id
  returning * into v_message;

  update public.chat_rooms
  set last_message = 'Xabar o‘chirildi', last_message_at = now()
  where id = v_message.room_id;

  return v_message;
end;
$$;

grant execute on function public.chat_delete_message(uuid) to authenticated;

alter table public.chat_rooms enable row level security;
alter table public.chat_room_members enable row level security;
alter table public.chat_messages enable row level security;

drop policy if exists "chat rooms select visible" on public.chat_rooms;
drop policy if exists "chat rooms insert authenticated" on public.chat_rooms;
drop policy if exists "chat rooms update visible" on public.chat_rooms;
drop policy if exists "chat rooms update managers" on public.chat_rooms;
drop policy if exists "chat members select visible" on public.chat_room_members;
drop policy if exists "chat members insert authenticated" on public.chat_room_members;
drop policy if exists "chat messages select visible" on public.chat_messages;
drop policy if exists "chat messages insert visible" on public.chat_messages;
drop policy if exists "chat messages update owner" on public.chat_messages;

create policy "chat rooms select visible" on public.chat_rooms for select to authenticated
using (public.chat_can_access_room(id));
create policy "chat rooms insert authenticated" on public.chat_rooms for insert to authenticated
with check (true);
create policy "chat rooms update managers" on public.chat_rooms for update to authenticated
using (public.chat_can_manage_room(id)) with check (public.chat_can_manage_room(id));

create policy "chat members select visible" on public.chat_room_members for select to authenticated
using (public.chat_can_access_room(room_id));
create policy "chat members insert authenticated" on public.chat_room_members for insert to authenticated
with check (profile_id = auth.uid() or public.is_super_admin());

create policy "chat messages select visible" on public.chat_messages for select to authenticated
using (public.chat_can_access_room(room_id));
create policy "chat messages insert visible" on public.chat_messages for insert to authenticated
with check (sender_id = auth.uid() and public.chat_can_access_room(room_id));
create policy "chat messages update owner" on public.chat_messages for update to authenticated
using (sender_id = auth.uid() or public.is_super_admin())
with check (sender_id = auth.uid() or public.is_super_admin());

do $$
begin
  begin
    alter publication supabase_realtime add table public.chat_rooms;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.chat_messages;
  exception when duplicate_object then null;
  end;
end $$;

-- =========================
-- Push notification device tokens
-- =========================
create table if not exists public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  company_id uuid references public.companies(id) on delete cascade,
  token text not null,
  platform text not null default 'android',
  device_id text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(profile_id, token)
);

alter table public.device_tokens enable row level security;

drop policy if exists "device tokens select own or super" on public.device_tokens;
drop policy if exists "device tokens insert own" on public.device_tokens;
drop policy if exists "device tokens update own" on public.device_tokens;
drop policy if exists "device tokens delete own or super" on public.device_tokens;

create policy "device tokens select own or super" on public.device_tokens for select to authenticated
using (profile_id = auth.uid() or public.is_super_admin());
create policy "device tokens insert own" on public.device_tokens for insert to authenticated
with check (profile_id = auth.uid());
create policy "device tokens update own" on public.device_tokens for update to authenticated
using (profile_id = auth.uid()) with check (profile_id = auth.uid());
create policy "device tokens delete own or super" on public.device_tokens for delete to authenticated
using (profile_id = auth.uid() or public.is_super_admin());

-- 2026-07 notification/chat realtime stability additions
alter table public.notifications add column if not exists chat_room_id uuid references public.chat_rooms(id) on delete cascade;
alter table public.notifications add column if not exists chat_message_id uuid references public.chat_messages(id) on delete cascade;

create table if not exists public.chat_typing (
  room_id uuid not null references public.chat_rooms(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  company_id uuid references public.companies(id) on delete cascade,
  is_typing boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key(room_id, profile_id)
);

alter table public.chat_typing enable row level security;

drop policy if exists "chat typing select visible" on public.chat_typing;
drop policy if exists "chat typing upsert self" on public.chat_typing;

create policy "chat typing select visible" on public.chat_typing for select to authenticated
using (public.chat_can_access_room(room_id));

create policy "chat typing upsert self" on public.chat_typing for all to authenticated
using (profile_id = auth.uid() and public.chat_can_access_room(room_id))
with check (profile_id = auth.uid() and public.chat_can_access_room(room_id));

do $$
begin
  begin
    alter publication supabase_realtime add table public.chat_typing;
  exception when duplicate_object then null;
  end;
end $$;

-- Make group room include all existing company members, so notification/member visibility is reliable.
create or replace function public.chat_ensure_group_room()
returns public.chat_rooms
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_room public.chat_rooms%rowtype;
begin
  select * into v_profile from public.profiles where id = auth.uid();
  if v_profile.id is null then
    raise exception 'chat_profile_not_found';
  end if;
  if v_profile.company_id is null then
    raise exception 'chat_company_not_found';
  end if;

  select * into v_room
  from public.chat_rooms
  where company_id = v_profile.company_id and type = 'group'
  order by created_at asc
  limit 1;

  if v_room.id is null then
    insert into public.chat_rooms(company_id, type, title, created_by, last_message, last_message_at)
    values (v_profile.company_id, 'group', 'Umumiy chat', auth.uid(), 'Umumiy chat yaratildi', now())
    returning * into v_room;
  end if;

  insert into public.chat_room_members(room_id, profile_id)
  select v_room.id, id from public.profiles where company_id = v_profile.company_id
  on conflict(room_id, profile_id) do nothing;

  return v_room;
end;
$$;

grant execute on function public.chat_ensure_group_room() to authenticated;


-- Chat read receipts for one/two tick logic
create table if not exists public.chat_message_reads (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.chat_messages(id) on delete cascade,
  room_id uuid not null references public.chat_rooms(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  read_at timestamptz not null default now(),
  unique(message_id, profile_id)
);

alter table public.chat_message_reads enable row level security;

drop policy if exists "chat message reads select members" on public.chat_message_reads;
drop policy if exists "chat message reads insert own" on public.chat_message_reads;

create policy "chat message reads select members" on public.chat_message_reads for select to authenticated
using (public.chat_can_access_room(room_id));

create policy "chat message reads insert own" on public.chat_message_reads for insert to authenticated
with check (profile_id = auth.uid() and public.chat_can_access_room(room_id));

do $$
begin
  begin
    alter publication supabase_realtime add table public.chat_message_reads;
  exception when duplicate_object then null;
  end;
end $$;

-- =========================
-- Super Admin hard cleanup / delete helpers
-- These functions are intentionally limited to public.is_super_admin().
-- They remove database rows permanently so old tickets, ads, chats and orphan rows do not remain.
-- =========================
create or replace function public.super_delete_chat_room(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_super_admin() then
    raise exception 'super_admin_required';
  end if;

  update public.chat_rooms set pinned_message_id = null where id = p_room_id;
  delete from public.chat_message_reads where room_id = p_room_id;
  delete from public.chat_typing where room_id = p_room_id;
  delete from public.notifications where chat_room_id = p_room_id;
  delete from public.chat_messages where room_id = p_room_id;
  delete from public.chat_room_members where room_id = p_room_id;
  delete from public.chat_rooms where id = p_room_id;
end;
$$;

grant execute on function public.super_delete_chat_room(uuid) to authenticated;

create or replace function public.super_delete_profile(p_profile_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_super_admin() then
    raise exception 'super_admin_required';
  end if;
  if exists(select 1 from public.profiles where id = p_profile_id and role = 'super_admin') then
    raise exception 'cannot_delete_super_admin';
  end if;

  update public.chat_rooms set pinned_message_id = null where pinned_message_id in (
    select id from public.chat_messages where sender_id = p_profile_id
  );
  delete from public.device_tokens where profile_id = p_profile_id;
  delete from public.chat_message_reads where profile_id = p_profile_id;
  delete from public.chat_typing where profile_id = p_profile_id;
  delete from public.notifications where profile_id = p_profile_id or sent_by = p_profile_id;
  delete from public.chat_messages where sender_id = p_profile_id;
  delete from public.chat_room_members where profile_id = p_profile_id;
  delete from public.tickets where created_by = p_profile_id;
  update public.tickets set accepted_by = null where accepted_by = p_profile_id;
  update public.tickets set completed_by = null where completed_by = p_profile_id;
  update public.companies set director_id = auth.uid() where director_id = p_profile_id;
  delete from public.profiles where id = p_profile_id;
end;
$$;

grant execute on function public.super_delete_profile(uuid) to authenticated;

create or replace function public.super_delete_company(p_company_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_super_admin() then
    raise exception 'super_admin_required';
  end if;

  update public.chat_rooms set pinned_message_id = null where company_id = p_company_id;
  delete from public.chat_message_reads where room_id in (select id from public.chat_rooms where company_id = p_company_id);
  delete from public.chat_typing where room_id in (select id from public.chat_rooms where company_id = p_company_id);
  delete from public.notifications where company_id = p_company_id;
  delete from public.chat_messages where room_id in (select id from public.chat_rooms where company_id = p_company_id);
  delete from public.chat_room_members where room_id in (select id from public.chat_rooms where company_id = p_company_id);
  delete from public.chat_rooms where company_id = p_company_id;
  delete from public.device_tokens where company_id = p_company_id or profile_id in (select id from public.profiles where company_id = p_company_id);
  delete from public.tickets where company_id = p_company_id;
  delete from public.buildings where company_id = p_company_id;
  delete from public.profiles where company_id = p_company_id and role <> 'super_admin';
  delete from public.companies where id = p_company_id;
end;
$$;

grant execute on function public.super_delete_company(uuid) to authenticated;

create or replace function public.super_cleanup_activity_data()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_super_admin() then
    raise exception 'super_admin_required';
  end if;

  update public.chat_rooms set pinned_message_id = null where id is not null;
  delete from public.chat_message_reads;
  delete from public.chat_typing;
  delete from public.notifications;
  delete from public.chat_messages;
  delete from public.chat_room_members;
  delete from public.chat_rooms;
  delete from public.tickets;
end;
$$;

grant execute on function public.super_cleanup_activity_data() to authenticated;


-- App-level settings used by Super Admin billing controls
create table if not exists public.app_settings (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);

alter table public.app_settings enable row level security;

drop policy if exists "app settings read authenticated" on public.app_settings;
drop policy if exists "app settings manage super admin" on public.app_settings;

create policy "app settings read authenticated"
on public.app_settings
for select
to authenticated
using (true);

create policy "app settings manage super admin"
on public.app_settings
for all
to authenticated
using (public.is_super_admin())
with check (public.is_super_admin());

insert into public.app_settings(key, value)
values ('global_monthly_price', '499000'::jsonb)
on conflict (key) do nothing;

-- Billing / subscription module
create table if not exists public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  status text not null default 'trial' check (status in ('trial','active','expired','blocked')),
  plan_name text not null default 'monthly',
  monthly_price integer not null default 499000,
  discount_percent integer not null default 0,
  discount_amount integer not null default 0,
  trial_ends_at timestamptz,
  current_period_start timestamptz,
  current_period_end timestamptz,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(company_id)
);

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  provider text not null default 'manual',
  provider_transaction_id text,
  amount integer not null,
  currency text not null default 'UZS',
  status text not null default 'paid',
  period_days integer not null default 30,
  paid_at timestamptz,
  note text,
  raw_payload jsonb,
  created_at timestamptz not null default now()
);

alter table public.subscriptions add column if not exists discount_percent integer not null default 0;
alter table public.subscriptions add column if not exists discount_amount integer not null default 0;
alter table public.subscriptions add column if not exists note text;
alter table public.payments add column if not exists period_days integer not null default 30;
alter table public.payments add column if not exists note text;

alter table public.subscriptions enable row level security;
alter table public.payments enable row level security;

drop policy if exists "subscriptions select own or super" on public.subscriptions;
drop policy if exists "subscriptions insert super" on public.subscriptions;
drop policy if exists "subscriptions update super" on public.subscriptions;
drop policy if exists "subscriptions delete super" on public.subscriptions;
drop policy if exists "payments select own or super" on public.payments;
drop policy if exists "payments insert super" on public.payments;
drop policy if exists "payments update super" on public.payments;
drop policy if exists "payments delete super" on public.payments;

create policy "subscriptions select own or super" on public.subscriptions for select to authenticated
using (public.is_super_admin() or company_id = public.my_company_id());
create policy "subscriptions insert super" on public.subscriptions for insert to authenticated
with check (public.is_super_admin() or company_id = public.my_company_id());
create policy "subscriptions update super" on public.subscriptions for update to authenticated
using (public.is_super_admin()) with check (public.is_super_admin());
create policy "subscriptions delete super" on public.subscriptions for delete to authenticated
using (public.is_super_admin());

create policy "payments select own or super" on public.payments for select to authenticated
using (public.is_super_admin() or company_id = public.my_company_id());
create policy "payments insert super" on public.payments for insert to authenticated
with check (public.is_super_admin());
create policy "payments update super" on public.payments for update to authenticated
using (public.is_super_admin()) with check (public.is_super_admin());
create policy "payments delete super" on public.payments for delete to authenticated
using (public.is_super_admin());

create or replace function public.ensure_company_subscription(p_company_id uuid)
returns public.subscriptions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_subscription public.subscriptions%rowtype;
  v_monthly_price integer := 499000;
begin
  if not public.is_super_admin()
     and not exists(select 1 from public.companies c where c.id = p_company_id and c.director_id = auth.uid())
     and p_company_id <> public.my_company_id() then
    raise exception 'billing_access_denied';
  end if;

  select coalesce((value #>> '{}')::integer, 499000)
  into v_monthly_price
  from public.app_settings
  where key = 'global_monthly_price';

  v_monthly_price := coalesce(v_monthly_price, 499000);

  insert into public.subscriptions(
    company_id,
    status,
    plan_name,
    monthly_price,
    discount_percent,
    discount_amount,
    trial_ends_at,
    current_period_start,
    current_period_end
  ) values (
    p_company_id,
    'trial',
    'monthly',
    v_monthly_price,
    0,
    0,
    now() + interval '7 days',
    null,
    null
  )
  on conflict (company_id) do update
  set updated_at = now()
  returning * into v_subscription;

  return v_subscription;
end;
$$;

grant execute on function public.ensure_company_subscription(uuid) to authenticated;

insert into public.subscriptions(company_id, status, plan_name, monthly_price, trial_ends_at)
select
  c.id,
  'trial',
  'monthly',
  coalesce((select (value #>> '{}')::integer from public.app_settings where key = 'global_monthly_price'), 499000),
  now() + interval '7 days'
from public.companies c
where not exists(select 1 from public.subscriptions s where s.company_id = c.id);

notify pgrst, 'reload schema';

create or replace function public.delete_my_direct_chat_room(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists(
    select 1
    from public.chat_rooms r
    join public.chat_room_members m on m.room_id = r.id
    where r.id = p_room_id
      and r.type = 'direct'
      and m.profile_id = auth.uid()
  ) then
    raise exception 'chat_delete_denied';
  end if;

  delete from public.notifications where chat_room_id = p_room_id;
  delete from public.chat_message_reads where room_id = p_room_id;
  delete from public.chat_typing where room_id = p_room_id;
  delete from public.chat_messages where room_id = p_room_id;
  delete from public.chat_room_members where room_id = p_room_id;
  delete from public.chat_rooms where id = p_room_id;
end;
$$;

grant execute on function public.delete_my_direct_chat_room(uuid) to authenticated;
notify pgrst, 'reload schema';

-- Super Admin scheduled push notifications
create table if not exists public.scheduled_notifications (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  send_time text not null check (send_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'),
  weekdays int[] not null default '{1,2,3,4,5,6,7}',
  specific_date date,
  is_active boolean not null default true,
  last_sent_for date,
  last_sent_at timestamptz,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint scheduled_notifications_weekday_range check (
    weekdays <@ array[1,2,3,4,5,6,7]
  )
);

alter table public.scheduled_notifications enable row level security;

drop policy if exists "super admins manage scheduled notifications" on public.scheduled_notifications;
create policy "super admins manage scheduled notifications"
on public.scheduled_notifications
for all
to authenticated
using (public.is_super_admin())
with check (public.is_super_admin());

create index if not exists scheduled_notifications_due_idx
on public.scheduled_notifications(is_active, send_time, specific_date, last_sent_for);

notify pgrst, 'reload schema';
