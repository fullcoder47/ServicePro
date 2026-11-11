-- Candidate additive migration; requires both 20261009 migrations first.
begin;
create schema if not exists servicepro_private;

alter table public.tickets add column if not exists request_id uuid;
alter table public.tickets add column if not exists requester_snapshot jsonb not null default '{}'::jsonb;
create unique index if not exists tickets_request_once on public.tickets(created_by,request_id) where request_id is not null;

create or replace function servicepro_private.create_profile_ticket(p_request_id uuid,p_description text)
returns public.tickets language plpgsql security definer set search_path='' as $$
declare p public.profiles%rowtype; a public.resident_addresses%rowtype; t public.tickets%rowtype;
begin
 if auth.uid() is null or p_request_id is null then raise exception 'authentication_required'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||p_request_id::text,0));
 select * into t from public.tickets where created_by=auth.uid() and request_id=p_request_id;
 if found then return t; end if;
 select * into p from public.profiles where id=auth.uid();
 select * into a from public.resident_addresses where profile_id=auth.uid();
 if p.company_id is null or length(trim(p.first_name))=0 or length(trim(p.last_name))=0 or
   coalesce(length(trim(p.phone)),0)=0 or coalesce(length(trim(a.neighborhood)),0)=0 or
   coalesce(length(trim(a.street)),0)=0 or coalesce(length(trim(a.house_number)),0)=0 then
   raise exception 'profile_address_required';
 end if;
 if coalesce(length(trim(p_description)),0)=0 or length(p_description)>10000 then raise exception 'invalid_description'; end if;
 insert into public.tickets(ticket_number,company_id,created_by,address_text,apartment_number,description,status,request_id,requester_snapshot)
 values(public.next_ticket_number(),p.company_id,p.id,concat_ws(', ',a.neighborhood,a.street,a.house_number),'',trim(p_description),'new',p_request_id,
 jsonb_build_object('first_name',p.first_name,'last_name',p.last_name,'phone',p.phone,'neighborhood',a.neighborhood,'street',a.street,'house_number',a.house_number)) returning * into t;
 return t;
end $$;
create or replace function public.servicepro_create_profile_ticket(p_request_id uuid,p_description text)
returns public.tickets language sql security invoker set search_path='' as $$ select servicepro_private.create_profile_ticket(p_request_id,p_description) $$;
revoke all on function servicepro_private.create_profile_ticket(uuid,text),public.servicepro_create_profile_ticket(uuid,text) from public,anon;
grant execute on function servicepro_private.create_profile_ticket(uuid,text),public.servicepro_create_profile_ticket(uuid,text) to authenticated;

create or replace function public.servicepro_save_ticket_contact(p_first text,p_last text,p_phone text,p_neighborhood text,p_street text,p_house text)
returns void language plpgsql security invoker set search_path='' as $$ begin
 if auth.uid() is null then raise exception 'authentication_required'; end if;
 if coalesce(length(trim(p_first)),0)=0 or coalesce(length(trim(p_last)),0)=0 or p_phone !~ '^\+?[0-9]{7,15}$' or
 coalesce(length(trim(p_neighborhood)),0)=0 or coalesce(length(trim(p_street)),0)=0 or coalesce(length(trim(p_house)),0)=0 then raise exception 'invalid_contact'; end if;
 update public.profiles set first_name=trim(p_first),last_name=trim(p_last),phone=trim(p_phone) where id=auth.uid();
 insert into public.resident_addresses(profile_id,neighborhood,street,house_number) values(auth.uid(),trim(p_neighborhood),trim(p_street),trim(p_house))
 on conflict(profile_id) do update set neighborhood=excluded.neighborhood,street=excluded.street,house_number=excluded.house_number;
end $$;
revoke all on function public.servicepro_save_ticket_contact(text,text,text,text,text,text) from public,anon;
grant execute on function public.servicepro_save_ticket_contact(text,text,text,text,text,text) to authenticated;

create table public.chat_preferences (
 room_id uuid not null references public.chat_rooms(id) on delete cascade,
 profile_id uuid not null references public.profiles(id) on delete cascade,
 muted_until timestamptz, text_scale numeric not null default 1 check(text_scale between 0.9 and 1.4),
 wallpaper text not null default 'default' check(wallpaper in ('default','blue','warm')),
 primary key(room_id,profile_id)
);
alter table public.chat_preferences enable row level security;
grant select,insert,update,delete on public.chat_preferences to authenticated;
create policy "chat preferences own" on public.chat_preferences for all to authenticated
 using(profile_id=auth.uid() and public.chat_can_access_room(room_id))
 with check(profile_id=auth.uid() and public.chat_can_access_room(room_id));

create table public.chat_reactions (
 message_id uuid not null references public.chat_messages(id) on delete cascade,
 profile_id uuid not null references public.profiles(id) on delete cascade,
 room_id uuid not null references public.chat_rooms(id) on delete cascade,
 emoji text not null check(emoji in ('👍','❤️','😂','😮','😢','🙏','🔥','👏')),
 primary key(message_id,profile_id)
);
create index chat_reactions_room on public.chat_reactions(room_id);
alter table public.chat_reactions enable row level security;
grant select,insert,update,delete on public.chat_reactions to authenticated;
create policy "reaction members read" on public.chat_reactions for select to authenticated
 using(public.chat_can_access_room(room_id));
create policy "reaction own write" on public.chat_reactions for all to authenticated
 using(profile_id=auth.uid() and public.chat_can_access_room(room_id))
 with check(profile_id=auth.uid() and public.chat_can_access_room(room_id) and exists(
 select 1 from public.chat_messages m where m.id=message_id and m.room_id=chat_reactions.room_id and not m.is_deleted));
-- Composite identity and supplied room are checked by RLS. A set operation is
-- idempotent so retries never toggle the reaction twice.
create or replace function public.servicepro_set_reaction(p_message_id uuid,p_room_id uuid,p_emoji text)
returns void language plpgsql security invoker set search_path='' as $$
begin
 if auth.uid() is null or not public.chat_can_access_room(p_room_id) then raise exception 'access_denied'; end if;
 if p_emoji is null then delete from public.chat_reactions where message_id=p_message_id and profile_id=auth.uid() and room_id=p_room_id;
 else insert into public.chat_reactions(message_id,profile_id,room_id,emoji) values(p_message_id,auth.uid(),p_room_id,p_emoji)
 on conflict(message_id,profile_id) do update set emoji=excluded.emoji,room_id=excluded.room_id; end if;
end $$;
revoke all on function public.servicepro_set_reaction(uuid,uuid,text) from public,anon;
grant execute on function public.servicepro_set_reaction(uuid,uuid,text) to authenticated;
do $$ begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') then
  alter publication supabase_realtime add table public.chat_reactions;
 end if;
end $$;

alter table public.notifications add column if not exists event_key text;
create unique index notification_event_once on public.notifications(profile_id,event_key) where event_key is not null;
create table servicepro_private.push_jobs (
 notification_id uuid primary key references public.notifications(id) on delete cascade,
 attempts integer not null default 0, available_at timestamptz not null default now(),
 leased_until timestamptz, lease_token uuid, delivered_at timestamptz,
 last_error text, delivered_tokens text[] not null default '{}'
);
alter table servicepro_private.push_jobs enable row level security;
revoke all on servicepro_private.push_jobs from public,anon,authenticated;

create or replace function servicepro_private.queue_notification() returns trigger
language plpgsql security definer set search_path='' as $$ begin
 if new.profile_id is not null then insert into servicepro_private.push_jobs(notification_id) values(new.id) on conflict do nothing; end if;
 return new;
end $$;
create trigger queue_notification after insert on public.notifications for each row execute function servicepro_private.queue_notification();

create or replace function servicepro_private.ticket_notification() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_title text; v_body text;
begin
 if tg_op='UPDATE' and new.status=old.status then return new; end if;
 v_title:=case new.status when 'new' then 'Yangi ariza' when 'in_progress' then 'Ariza jarayonda' when 'completed' then 'Ariza bajarildi' when 'closed' then 'Ariza yopildi' else 'Ariza yangilandi' end;
 v_body:=new.ticket_number||': '||new.address_text;
 insert into public.notifications(profile_id,ticket_id,title,body,notification_type,company_id,event_key)
 select p.id,new.id,v_title,v_body,'ticket_'||new.status,new.company_id,'ticket:'||new.id||':'||new.status
 from public.profiles p where p.id=new.created_by or p.id=new.accepted_by or
 (p.company_id=new.company_id and p.role in ('director','admin'))
 on conflict(profile_id,event_key) where event_key is not null do nothing;
 return new;
end $$;
create trigger ticket_event_notification after insert or update of status on public.tickets
 for each row execute function servicepro_private.ticket_notification();

create or replace function servicepro_private.chat_notification() returns trigger
language plpgsql security definer set search_path='' as $$
declare r public.chat_rooms%rowtype; v_title text;
begin
 select * into r from public.chat_rooms where id=new.room_id;
 select trim(first_name||' '||last_name) into v_title from public.profiles where id=new.sender_id;
 insert into public.notifications(profile_id,title,body,notification_type,sent_by,company_id,chat_room_id,chat_message_id,event_key)
 select p.id,coalesce(nullif(v_title,''),'Yangi xabar'),coalesce(nullif(new.text,''),'Media yuborildi'),'chat',new.sender_id,r.company_id,r.id,new.id,'chat:'||new.id
 from public.profiles p where p.id<>new.sender_id and
 ((r.type='group' and p.company_id=r.company_id) or exists(select 1 from public.chat_room_members m where m.room_id=r.id and m.profile_id=p.id))
 on conflict(profile_id,event_key) where event_key is not null do nothing;
 return new;
end $$;
create trigger chat_event_notification after insert on public.chat_messages for each row execute function servicepro_private.chat_notification();

-- Legacy clients may still attempt their own ticket/chat notifications. Their
-- failed duplicate inserts are harmless; authoritative events originate above.
drop policy if exists "notifications insert company" on public.notifications;
create policy "notifications trusted campaigns" on public.notifications for insert to authenticated
 with check((public.is_super_admin() and notification_type in ('advertisement','scheduled')) or
 (notification_type='advertisement' and sent_by=auth.uid() and public.my_role() in ('director','admin') and company_id=public.my_company_id()
 and (profile_id is null or exists(select 1 from public.profiles p where p.id=profile_id and p.company_id=public.my_company_id()))));

create or replace function public.servicepro_enqueue_schedules() returns integer
language plpgsql security definer set search_path='' as $$
declare s public.scheduled_notifications%rowtype; v_now timestamp:=now() at time zone 'Asia/Tashkent'; n integer:=0;
begin
 for s in select * from public.scheduled_notifications where is_active and
 send_time<=to_char(v_now,'HH24:MI') and (last_sent_for is null or last_sent_for<v_now::date) and
 ((specific_date is not null and specific_date=v_now::date) or (specific_date is null and extract(isodow from v_now)::integer=any(weekdays)))
 for update skip locked loop
  insert into public.notifications(profile_id,title,body,notification_type,audience,ad_group_id,event_key)
  select id,s.title,s.body,'scheduled','all','scheduled_'||s.id||'_'||v_now::date,'schedule:'||s.id||':'||v_now::date
  from public.profiles where role<>'super_admin'
  on conflict(profile_id,event_key) where event_key is not null do nothing;
  update public.scheduled_notifications set last_sent_for=v_now::date,last_sent_at=now() where id=s.id;
  n:=n+1;
 end loop;
 return n;
end $$;

create or replace function public.servicepro_claim_push_jobs(p_limit integer default 20) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 with picked as (select notification_id from servicepro_private.push_jobs
 where delivered_at is null and attempts<12 and available_at<=now() and (leased_until is null or leased_until<now())
 order by available_at for update skip locked limit least(greatest(p_limit,1),50)),
 claimed as (update servicepro_private.push_jobs j set attempts=j.attempts+1,leased_until=now()+interval '5 minutes',lease_token=gen_random_uuid()
 from picked where picked.notification_id=j.notification_id returning j.*)
 select coalesce(jsonb_agg(to_jsonb(n)||jsonb_build_object('lease_token',c.lease_token,'attempts',c.attempts,'delivered_tokens',c.delivered_tokens)),'[]'::jsonb)
 into result from claimed c join public.notifications n on n.id=c.notification_id;
 return result;
end $$;
create or replace function public.servicepro_finish_push_job(p_id uuid,p_lease uuid,p_ok boolean,p_tokens text[],p_error text default '') returns void
language sql security definer set search_path='' as $$
 update servicepro_private.push_jobs set delivered_at=case when p_ok then now() else null end,
 available_at=now()+make_interval(secs=>least(3600,30*power(2,least(attempts,7))::integer)),
 leased_until=null,lease_token=null,last_error=left(p_error,400),
 delivered_tokens=array(select distinct unnest(delivered_tokens||coalesce(p_tokens,'{}')))
 where notification_id=p_id and lease_token=p_lease;
$$;
revoke all on function public.servicepro_enqueue_schedules(),public.servicepro_claim_push_jobs(integer),public.servicepro_finish_push_job(uuid,uuid,boolean,text[],text) from public,anon,authenticated;
grant execute on function public.servicepro_enqueue_schedules(),public.servicepro_claim_push_jobs(integer),public.servicepro_finish_push_job(uuid,uuid,boolean,text[],text) to service_role;
revoke all on function servicepro_private.queue_notification(),servicepro_private.ticket_notification(),servicepro_private.chat_notification() from public,anon,authenticated;
create or replace function servicepro_private.register_device(p_token text,p_platform text) returns void
language plpgsql security definer set search_path='' as $$
declare p public.profiles%rowtype;
begin
 if auth.uid() is null or coalesce(length(p_token),0)<20 or length(p_token)>4096 or p_platform not in ('android','ios') then raise exception 'invalid_device'; end if;
 select * into p from public.profiles where id=auth.uid();
 if not found then raise exception 'profile_required'; end if;
 update public.device_tokens set is_active=false where token=p_token and profile_id<>p.id;
 insert into public.device_tokens(profile_id,company_id,token,platform,is_active,updated_at)
 values(p.id,p.company_id,p_token,p_platform,true,now()) on conflict(profile_id,token)
 do update set company_id=excluded.company_id,platform=excluded.platform,is_active=true,updated_at=now();
end $$;
create or replace function public.servicepro_register_device(p_token text,p_platform text) returns void
language sql security invoker set search_path='' as $$ select servicepro_private.register_device(p_token,p_platform) $$;
revoke all on function servicepro_private.register_device(text,text),public.servicepro_register_device(text,text) from public,anon;
grant execute on function servicepro_private.register_device(text,text),public.servicepro_register_device(text,text) to authenticated;

-- Notification recipients can acknowledge delivery, but cannot rewrite a
-- pending job's recipient or payload. Campaign authors can edit campaign media.
create or replace function servicepro_private.guard_notification_update() returns trigger
language plpgsql security definer set search_path='' as $$ begin
 if auth.uid() is null then return new; end if;
 if (new.profile_id,new.ticket_id,new.chat_room_id,new.chat_message_id,new.sent_by,new.company_id,new.notification_type,new.event_key)
 is distinct from (old.profile_id,old.ticket_id,old.chat_room_id,old.chat_message_id,old.sent_by,old.company_id,old.notification_type,old.event_key)
 then raise exception 'notification_identity_immutable'; end if;
 if not public.is_super_admin() and old.sent_by is distinct from auth.uid() and
 (to_jsonb(new)-'is_read') is distinct from (to_jsonb(old)-'is_read') then raise exception 'notification_read_only'; end if;
 return new;
end $$;
create trigger guard_notification_update before update on public.notifications for each row execute function servicepro_private.guard_notification_update();
create or replace function servicepro_private.guard_ticket_snapshot() returns trigger
language plpgsql security definer set search_path='' as $$ begin
 if new.requester_snapshot is distinct from old.requester_snapshot or new.request_id is distinct from old.request_id
 then raise exception 'ticket_snapshot_immutable'; end if;
 return new;
end $$;
create trigger guard_ticket_snapshot before update on public.tickets for each row execute function servicepro_private.guard_ticket_snapshot();
revoke all on function servicepro_private.guard_notification_update(),servicepro_private.guard_ticket_snapshot() from public,anon,authenticated;

commit;
