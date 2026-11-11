-- Requires the three earlier ServicePro migrations. No existing activity deleted.
begin;
alter table public.tickets add column if not exists accepted_by_actor uuid references public.profiles(id) on delete set null;
alter table public.tickets add column if not exists completed_by_actor uuid references public.profiles(id) on delete set null;
alter table public.worker_ratings add column if not exists comment text not null default '';
create index if not exists push_jobs_ready on servicepro_private.push_jobs(available_at) where delivered_at is null;
create index if not exists worker_rating_lookup on public.worker_ratings(worker_id);
create index if not exists tickets_reminder_queue on public.tickets(company_id,status,created_at) where status in ('new','in_progress');

create or replace function servicepro_private.transition_ticket_worker(p_ticket_id uuid,p_complete boolean,p_description text,p_media text[],p_worker_id uuid)
returns public.tickets language plpgsql security definer set search_path='' as $$
declare me public.profiles; item public.tickets; worker public.profiles; chosen uuid;
begin
 select * into me from public.profiles where id=auth.uid();
 if not found or me.role not in ('super_admin','director','admin','worker') then raise exception 'staff_required'; end if;
 select * into item from public.tickets where id=p_ticket_id for update;
 if not found or (me.role<>'super_admin' and me.company_id is distinct from item.company_id) then raise exception 'ticket_unavailable'; end if;
 chosen:=case when me.role='worker' then me.id else coalesce(p_worker_id,item.accepted_by) end;
 select * into worker from public.profiles where id=chosen and role='worker' and company_id=item.company_id;
 if not found then raise exception 'worker_required'; end if;
 if me.role='worker' and p_worker_id is not null and p_worker_id<>me.id then raise exception 'worker_access_denied'; end if;
 if p_complete then
  if item.status not in ('in_progress','completed') or (me.role='worker' and item.accepted_by is distinct from me.id) then raise exception 'ticket_not_assigned'; end if;
  -- Retry after a lost response must not create another completion event.
  if item.status='completed' then
   if item.completed_by=chosen and item.completion_description=trim(p_description) and item.completion_attachments=p_media then return item; end if;
   raise exception 'ticket_already_completed';
  end if;
  if coalesce(trim(p_description),'')='' or coalesce(array_length(p_media,1),0)=0 then raise exception 'completion_media_required'; end if;
  update public.tickets set status='completed',completed_by=chosen,completed_by_actor=me.id,completed_at=now(),
   completion_description=trim(p_description),completion_attachments=p_media where id=item.id returning * into item;
 else
  if item.status='in_progress' and item.accepted_by=chosen then return item; end if;
  if item.status<>'new' then raise exception 'ticket_already_accepted'; end if;
  update public.tickets set status='in_progress',accepted_by=chosen,accepted_by_actor=me.id,accepted_at=now()
   where id=item.id returning * into item;
 end if;
 return item;
end $$;
create or replace function public.servicepro_transition_ticket_worker(p_ticket_id uuid,p_complete boolean,p_description text,p_media text[],p_worker_id uuid default null)
returns public.tickets language sql security invoker set search_path='' as $$
 select servicepro_private.transition_ticket_worker(p_ticket_id,p_complete,p_description,p_media,p_worker_id)
$$;
revoke all on function servicepro_private.transition_ticket_worker(uuid,boolean,text,text[],uuid),public.servicepro_transition_ticket_worker(uuid,boolean,text,text[],uuid) from public,anon;
grant execute on function servicepro_private.transition_ticket_worker(uuid,boolean,text,text[],uuid),public.servicepro_transition_ticket_worker(uuid,boolean,text,text[],uuid) to authenticated;

create or replace function servicepro_private.set_worker_details(p_worker_id uuid,p_job text,p_salary numeric)
returns void language plpgsql security definer set search_path='' as $$
declare me public.profiles; worker public.profiles;
begin
 select * into me from public.profiles where id=auth.uid();
 select * into worker from public.profiles where id=p_worker_id and role='worker';
 if me.id is null or worker.id is null or not(me.role='super_admin' or (me.role in ('director','admin') and me.company_id=worker.company_id)) then raise exception 'worker_access_denied'; end if;
 if coalesce(trim(p_job),'')='' or p_salary<0 or p_salary>999999999999 then raise exception 'invalid_worker_details'; end if;
 update public.profiles set job_title=trim(p_job) where id=worker.id;
 if p_salary is null then delete from public.worker_payroll where profile_id=worker.id;
 else insert into public.worker_payroll(profile_id,monthly_salary) values(worker.id,p_salary)
 on conflict(profile_id) do update set monthly_salary=excluded.monthly_salary,updated_at=now(); end if;
 insert into public.notifications(profile_id,title,body,notification_type,company_id,sent_by,event_key)
 values(worker.id,'Ishchi ma’lumotlari yangilandi','Lavozim yoki oylik maoshingiz yangilandi.','worker_updated',worker.company_id,me.id,'worker:'||worker.id||':'||gen_random_uuid());
end $$;
create or replace function public.servicepro_set_worker_details(p_worker_id uuid,p_job text,p_salary numeric default null)
returns void language sql security invoker set search_path='' as $$ select servicepro_private.set_worker_details(p_worker_id,p_job,p_salary) $$;
revoke all on function servicepro_private.set_worker_details(uuid,text,numeric),public.servicepro_set_worker_details(uuid,text,numeric) from public,anon;
grant execute on function servicepro_private.set_worker_details(uuid,text,numeric),public.servicepro_set_worker_details(uuid,text,numeric) to authenticated;

create or replace function servicepro_private.guard_worker_rating() returns trigger language plpgsql security definer set search_path='' as $$
declare t public.tickets; p public.profiles;
begin
 select * into t from public.tickets where id=new.ticket_id;
 select * into p from public.profiles where id=new.worker_id;
 if t.created_by is distinct from new.rated_by or t.completed_by is distinct from new.worker_id or t.status not in ('completed','closed') or
 p.role<>'worker' or p.company_id is distinct from t.company_id or not exists(select 1 from public.profiles where id=new.rated_by and role='user')
 then raise exception 'invalid_rating'; end if;
 if length(new.comment)>2000 then raise exception 'rating_comment_too_long'; end if;
 return new;
end $$;
drop trigger if exists guard_worker_rating on public.worker_ratings;
create trigger guard_worker_rating before insert on public.worker_ratings for each row execute function servicepro_private.guard_worker_rating();
create or replace function public.servicepro_rate_work(p_ticket_id uuid,p_score integer,p_comment text default '') returns void
language plpgsql security invoker set search_path='' as $$
declare worker uuid;
begin
 if auth.uid() is null then raise exception 'authentication_required'; end if;
 select completed_by into worker from public.tickets where id=p_ticket_id and created_by=auth.uid() and status in ('completed','closed');
 if worker is null then raise exception 'rating_unavailable'; end if;
 insert into public.worker_ratings(ticket_id,rated_by,worker_id,score,comment)
 values(p_ticket_id,auth.uid(),worker,p_score,trim(coalesce(p_comment,''))) on conflict(ticket_id) do nothing;
end $$;
revoke all on function public.servicepro_rate_work(uuid,integer,text) from public,anon;
grant execute on function public.servicepro_rate_work(uuid,integer,text) to authenticated;

create or replace function servicepro_private.team_directory() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare me public.profiles; result jsonb;
begin
 select * into me from public.profiles where id=auth.uid();
 if not found then raise exception 'authentication_required'; end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',p.id,'company_id',p.company_id,'first_name',p.first_name,'last_name',p.last_name,'phone',p.phone,'avatar_url',p.avatar_url,'job_title',p.job_title,
  'completed_count',(select count(*) from public.tickets t where t.completed_by=p.id and t.status in ('completed','closed')),
  'busy',exists(select 1 from public.tickets t where t.accepted_by=p.id and t.status='in_progress'),
  'rating',(select round(avg(r.score)::numeric,1) from public.worker_ratings r where r.worker_id=p.id),
  'rating_count',(select count(*) from public.worker_ratings r where r.worker_id=p.id),
  'star_total',(select coalesce(sum(r.score),0) from public.worker_ratings r where r.worker_id=p.id),
  'monthly_salary',case when me.role='super_admin' or me.id=p.id or (me.company_id=p.company_id and me.role in ('director','admin')) then (select w.monthly_salary from public.worker_payroll w where w.profile_id=p.id) else null end
 ) order by p.first_name),'[]'::jsonb) into result
 from public.profiles p where p.role='worker' and (me.role='super_admin' or p.company_id=me.company_id);
 return result;
end $$;
create or replace function servicepro_private.rating_notification() returns trigger language plpgsql security definer set search_path='' as $$
declare c uuid;
begin
 select company_id into c from public.tickets where id=new.ticket_id;
 insert into public.notifications(profile_id,ticket_id,title,body,notification_type,company_id,event_key)
 select id,new.ticket_id,'Bajarilgan ish baholandi',new.score||' / 5 yulduz. '||left(new.comment,120),'worker_rating',c,'rating:'||new.ticket_id
 from public.profiles where id=new.worker_id or (company_id=c and role in ('director','admin'))
 on conflict(profile_id,event_key) where event_key is not null do nothing;
 return new;
end $$;
create trigger worker_rating_notification after insert on public.worker_ratings for each row execute function servicepro_private.rating_notification();

create or replace function servicepro_private.ticket_notification() returns trigger language plpgsql security definer set search_path='' as $$
declare title text; body text; worker_name text;
begin
 if tg_op='UPDATE' and new.status=old.status then return new; end if;
 title:=case new.status when 'new' then 'Yangi ariza' when 'in_progress' then 'Ariza ishchiga biriktirildi' when 'completed' then 'Ariza bajarildi' else 'Ariza yopildi' end;
 select trim(first_name||' '||last_name) into worker_name from public.profiles where id=case when new.status='completed' then new.completed_by else new.accepted_by end;
 body:=new.ticket_number||': '||new.address_text||case when worker_name is not null then '. Ishchi: '||worker_name else '' end;
 insert into public.notifications(profile_id,ticket_id,title,body,notification_type,company_id,event_key)
 select p.id,new.id,title,body,'ticket_'||new.status,new.company_id,'ticket:'||new.id||':'||new.status
 from public.profiles p where p.id=new.created_by or p.id=new.accepted_by or p.id=new.completed_by or
 (p.company_id=new.company_id and (p.role in ('director','admin') or (new.status='new' and p.role='worker')))
 on conflict(profile_id,event_key) where event_key is not null do nothing;
 return new;
end $$;

-- Twice daily at 09:00 and 18:00 Asia/Tashkent, at most once per slot/recipient.
create or replace function public.servicepro_enqueue_ticket_reminders() returns integer language plpgsql security definer set search_path='' as $$
declare v_now timestamp:=now() at time zone 'Asia/Tashkent'; slot text; affected integer;
begin
 slot:=case when v_now::time >= time '18:00' then '18' when v_now::time >= time '09:00' then '09' else null end;
 if slot is null then return 0; end if;
 insert into public.notifications(profile_id,ticket_id,title,body,notification_type,company_id,event_key)
 select p.id,t.id,'Diqqat! Ariza hali bajarilmagan',t.ticket_number||': '||t.address_text||'. Arizani kechiktirmang: ishni bajaring va natijani yuboring.',
 'ticket_reminder',t.company_id,'reminder:'||t.id||':'||v_now::date||':'||slot
 from public.tickets t join public.profiles author on author.id=t.created_by and author.role='user'
 join public.profiles p on p.company_id=t.company_id and (p.role in ('director','admin') or
 (p.role='worker' and (t.accepted_by is null or t.accepted_by=p.id)))
 where t.status in ('new','in_progress') and t.created_at <= (v_now::date+case slot when '09' then time '09:00' else time '18:00' end) at time zone 'Asia/Tashkent'
 on conflict(profile_id,event_key) where event_key is not null do nothing;
 get diagnostics affected=row_count;
 return affected;
end $$;
revoke all on function public.servicepro_enqueue_ticket_reminders() from public,anon,authenticated;
grant execute on function public.servicepro_enqueue_ticket_reminders() to service_role;

create or replace function servicepro_private.cleanup_company(p_company_id uuid,p_scope text,p_room_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare n integer;
begin
 if auth.uid() is null or not public.is_super_admin() then raise exception 'super_admin_required'; end if;
 if not exists(select 1 from public.companies where id=p_company_id) then raise exception 'company_unavailable'; end if;
 if p_scope='chats' then
  if p_room_id is not null and not exists(select 1 from public.chat_rooms where id=p_room_id and company_id=p_company_id) then raise exception 'room_unavailable'; end if;
  update public.chat_rooms set pinned_message_id=null,last_message=null,last_message_at=now() where company_id=p_company_id and (p_room_id is null or id=p_room_id);
  delete from public.notifications where chat_room_id in(select id from public.chat_rooms where company_id=p_company_id and (p_room_id is null or id=p_room_id));
  delete from public.chat_message_reads where room_id in(select id from public.chat_rooms where company_id=p_company_id and (p_room_id is null or id=p_room_id));
  delete from public.chat_reactions where room_id in(select id from public.chat_rooms where company_id=p_company_id and (p_room_id is null or id=p_room_id));
  delete from public.chat_messages where room_id in(select id from public.chat_rooms where company_id=p_company_id and (p_room_id is null or id=p_room_id));
 elsif p_scope='tickets' then
  delete from public.tickets where company_id=p_company_id;
 elsif p_scope='ads' then
  delete from public.notifications where company_id=p_company_id and notification_type='advertisement';
 else raise exception 'invalid_cleanup_scope'; end if;
 get diagnostics n=row_count;
 return jsonb_build_object('removed',n);
end $$;
create or replace function public.servicepro_cleanup_company(p_company_id uuid,p_scope text,p_room_id uuid default null) returns jsonb
language sql security invoker set search_path='' as $$ select servicepro_private.cleanup_company(p_company_id,p_scope,p_room_id) $$;
revoke all on function servicepro_private.cleanup_company(uuid,text,uuid),public.servicepro_cleanup_company(uuid,text,uuid) from public,anon;
grant execute on function servicepro_private.cleanup_company(uuid,text,uuid),public.servicepro_cleanup_company(uuid,text,uuid) to authenticated;

create or replace function servicepro_private.delete_chat_messages(p_company_id uuid,p_room_id uuid,p_message_ids uuid[]) returns integer
language plpgsql security definer set search_path='' as $$
declare n integer;
begin
 if auth.uid() is null or not public.is_super_admin() then raise exception 'super_admin_required'; end if;
 if not exists(select 1 from public.chat_rooms where id=p_room_id and company_id=p_company_id) then raise exception 'room_unavailable'; end if;
 if coalesce(cardinality(p_message_ids),0)=0 or cardinality(p_message_ids)>500 then raise exception 'invalid_selection'; end if;
 if exists(select 1 from unnest(p_message_ids) selected(id) where not exists(select 1 from public.chat_messages m where m.id=selected.id and m.room_id=p_room_id)) then raise exception 'message_unavailable'; end if;
 update public.chat_rooms set pinned_message_id=null where id=p_room_id and pinned_message_id=any(p_message_ids);
 delete from public.notifications where chat_message_id=any(p_message_ids);
 delete from public.chat_messages where room_id=p_room_id and id=any(p_message_ids);
 get diagnostics n=row_count;
 update public.chat_rooms set last_message=(select case when text='' then 'Media' else text end from public.chat_messages where room_id=p_room_id order by created_at desc limit 1),
 last_message_at=coalesce((select max(created_at) from public.chat_messages where room_id=p_room_id),now()) where id=p_room_id;
 return n;
end $$;
create or replace function public.servicepro_delete_chat_messages(p_company_id uuid,p_room_id uuid,p_message_ids uuid[]) returns integer
language sql security invoker set search_path='' as $$ select servicepro_private.delete_chat_messages(p_company_id,p_room_id,p_message_ids) $$;
revoke all on function servicepro_private.delete_chat_messages(uuid,uuid,uuid[]),public.servicepro_delete_chat_messages(uuid,uuid,uuid[]) from public,anon;
grant execute on function servicepro_private.delete_chat_messages(uuid,uuid,uuid[]),public.servicepro_delete_chat_messages(uuid,uuid,uuid[]) to authenticated;
revoke all on function servicepro_private.guard_worker_rating(),servicepro_private.rating_notification() from public,anon,authenticated;
-- An INSERT wakes the worker; the existing cron is the retry fallback.
create or replace function servicepro_private.queue_notification() returns trigger
language plpgsql security definer set search_path='' as $$
declare job_secret text;
begin
 if new.profile_id is not null then
  insert into servicepro_private.push_jobs(notification_id) values(new.id) on conflict do nothing;
  if coalesce(current_setting('servicepro.push_nudged',true),'')<>'true' and to_regclass('vault.decrypted_secrets') is not null and to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is not null then
   begin
    perform set_config('servicepro.push_nudged','true',true);
    execute 'select decrypted_secret from vault.decrypted_secrets where name=$1 limit 1' into job_secret using 'notification_job_secret';
    if job_secret is not null then
     execute 'select net.http_post(url:=$1,headers:=$2,body:=$3,timeout_milliseconds:=15000)'
     using 'https://inbqjyypfpfqnpcjqkqn.supabase.co/functions/v1/notification-worker',
      jsonb_build_object('Content-Type','application/json','x-job-secret',job_secret),'{}'::jsonb;
    end if;
   exception when others then null; -- Durable cron retries remain available.
   end;
  end if;
 end if;
 return new;
end $$;

notify pgrst,'reload schema';
commit;
