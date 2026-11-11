import { PGlite } from '@electric-sql/pglite';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
const db = new PGlite();
const root=process.env.SERVICEPRO_PROJECT;
if(!root)throw new Error('Set SERVICEPRO_PROJECT to the project directory');
const original = fs.readFileSync(root+'/supabase/servicepro_schema.sql','utf8');
let schema = original.slice(original.indexOf('create table if not exists public.companies'), original.indexOf('alter table public.companies enable'));
// Fixture loads the actual original table shapes; define only helpers this
// migration depends on, with the same authorization semantics as the project.
schema = schema.slice(0,schema.indexOf('create or replace function public.is_super_admin'));
await db.exec(`create role anon; create role authenticated; create role service_role;
create schema auth; create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
create function auth.jwt() returns jsonb language sql stable as $$ select jsonb_build_object('email',current_setting('request.jwt.claim.email',true)) $$;
grant usage on schema auth to anon,authenticated; grant execute on all functions in schema auth to anon,authenticated;
${schema}
create function public.is_super_admin() returns boolean language sql stable security definer set search_path='' as $$ select exists(select 1 from public.profiles where id=auth.uid() and role='super_admin') $$;
create function public.my_company_id() returns uuid language sql stable security definer set search_path='' as $$ select company_id from public.profiles where id=auth.uid() $$;
create function public.my_role() returns text language sql stable security definer set search_path='' as $$ select role from public.profiles where id=auth.uid() $$;
alter table public.profiles enable row level security;
alter table public.companies enable row level security;
alter table public.tickets enable row level security;
grant all on public.profiles,public.companies,public.tickets to authenticated;
create policy "profiles select own company or super" on public.profiles for select to authenticated using(public.is_super_admin() or id=auth.uid() or company_id=public.my_company_id());
create policy "profiles update self or super" on public.profiles for update to authenticated using(id=auth.uid() or public.is_super_admin()) with check(id=auth.uid() or public.is_super_admin());
create policy "tickets update company managers or owner close" on public.tickets for update to authenticated using(public.is_super_admin() or (company_id=public.my_company_id() and public.my_role() in ('director','admin')) or (created_by=auth.uid() and status in ('new','completed'))) with check(public.is_super_admin() or (company_id=public.my_company_id() and public.my_role() in ('director','admin')) or created_by=auth.uid());
`);
await db.exec(fs.readFileSync(root+'/supabase/migrations/20261009122140_guest_staff_access.sql','utf8'));
await db.exec(fs.readFileSync(root+'/supabase/migrations/20261009133514_shared_company_staff_code.sql','utf8'));
const ids = {super:'00000000-0000-0000-0000-000000000001',resident:'00000000-0000-0000-0000-000000000002',worker:'00000000-0000-0000-0000-000000000003',other:'00000000-0000-0000-0000-000000000004',company:'10000000-0000-0000-0000-000000000001',company2:'10000000-0000-0000-0000-000000000002',ticket:'20000000-0000-0000-0000-000000000001'};
for (const id of [ids.super,ids.resident,ids.worker,ids.other]) await db.query('insert into auth.users values($1)',[id]);
await db.query("insert into public.profiles(id,role,first_name,email) values($1,'super_admin','Admin','admin@test.local')",[ids.super]);
for (const [id,name] of [[ids.company,'BIG SCAN AS PLYUS'],[ids.company2,'Other']]) await db.query("insert into public.companies(id,name,join_password,director_id) values($1,$2,$2,$3)",[id,name,ids.super]);
async function asUser(id,email='') {await db.exec('reset role'); await db.query("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claim.email',$2,false)",[id??'',email]);await db.exec(`set role ${id?'authenticated':'anon'}`);}
let tests=0;
async function check(name,fn) {await fn();tests++;console.log('PASS',name);}
await check('guest directory exposes no passwords',async()=>{await asUser(null);const r=await db.query('select * from public.servicepro_company_directory()');assert.equal(r.rows.length,2);assert.deepEqual(Object.keys(r.rows[0]).sort(),['created_at','id','name']);});
const residentEmail='user_'+ids.company.replaceAll('-','')+'_998901234567@servicepro.local';
await check('resident onboarding and stored address',async()=>{await asUser(ids.resident,residentEmail);await db.query("select public.servicepro_complete_resident($1,'Ali','Vali','998901234567','Mahalla','Street','10','uz')",[ids.company]);const r=await db.query('select p.role,a.house_number from public.profiles p join public.resident_addresses a on a.profile_id=p.id where p.id=auth.uid()');assert.equal(r.rows[0].role,'user');assert.equal(r.rows[0].house_number,'10');});
await check('self role escalation rejected',async()=>{await assert.rejects(db.query("update public.profiles set role='super_admin' where id=auth.uid()"));});
await check('self company reassignment rejected',async()=>{await assert.rejects(db.query('update public.profiles set company_id=$1 where id=auth.uid()',[ids.company2]));});
await check('resident cannot create company',async()=>{await assert.rejects(db.query("insert into public.companies(name,join_password,director_id) values('Bad','bad',auth.uid())"));});
await check('resident cannot issue staff invite',async()=>{await assert.rejects(db.query("select public.servicepro_create_staff_invite($1,'director','x','A','B')",[ids.company]));});
const hash = (await import('node:crypto')).createHash('sha256').update(ids.company+'|vali|ali').digest('hex').slice(0,48);const workerEmail='staff_'+hash+'@servicepro.local';let code;
await check('super admin issues scoped invite',async()=>{await asUser(ids.super,'admin@test.local');const r=await db.query("select public.servicepro_create_staff_invite($1,'worker',$2,'Vali','Ali') code",[ids.company,workerEmail]);code=r.rows[0].code;assert.equal(code.length,32);});
await check('wrong role does not redeem code',async()=>{await asUser(ids.worker,workerEmail);await assert.rejects(db.query("select public.servicepro_claim_staff_invite($1,'director',$2,'Vali','Ali','Electrician','uz')",[ids.company,code]));});
await check('worker invitation grants only worker role',async()=>{await db.query("select public.servicepro_claim_staff_invite($1,'worker',$2,'Vali','Ali','Electrician','uz')",[ids.company,code]);const r=await db.query('select role from public.profiles where id=auth.uid()');assert.equal(r.rows[0].role,'worker');});
await check('invitation cannot be reused',async()=>{await assert.rejects(db.query("select public.servicepro_claim_staff_invite($1,'worker',$2,'Vali','Ali','Electrician','uz')",[ids.company,code]));});
await db.exec('reset role');await db.query('insert into public.worker_payroll(profile_id,monthly_salary) values($1,1234567)',[ids.worker]);
await db.query("insert into public.tickets(id,ticket_number,company_id,created_by,address_text,apartment_number,description) values($1,'SP-TEST',$2,$3,'A','1','Leak')",[ids.ticket,ids.company,ids.resident]);
await check('residents cannot read salary directly or via directory',async()=>{await asUser(ids.resident,residentEmail);assert.equal((await db.query('select * from public.worker_payroll')).rows.length,0);const r=await db.query('select public.servicepro_team_directory() data');assert.equal(r.rows[0].data[0].monthly_salary,null);});
await check('worker claims new ticket atomically',async()=>{await asUser(ids.worker,workerEmail);await db.query("select public.servicepro_transition_ticket($1,false,'','{}')",[ids.ticket]);await assert.rejects(db.query("select public.servicepro_transition_ticket($1,false,'','{}')",[ids.ticket]));});
await check('completion requires media',async()=>{await assert.rejects(db.query("select public.servicepro_transition_ticket($1,true,'Done','{}')",[ids.ticket]));});
await check('assigned worker completes with evidence',async()=>{await db.query("select public.servicepro_transition_ticket($1,true,'Done',ARRAY['test-photo'])",[ids.ticket]);});
await check('resident rates own completed ticket only',async()=>{await asUser(ids.resident,residentEmail);await db.query('insert into public.worker_ratings(ticket_id,rated_by,worker_id,score) values($1,auth.uid(),$2,5)',[ids.ticket,ids.worker]);const r=await db.query('select public.servicepro_team_directory() data');assert.equal(Number(r.rows[0].data[0].rating),5);});
await check('resident cannot modify ticket creator',async()=>{await assert.rejects(db.query('update public.tickets set created_by=$1 where id=$2',[ids.worker,ids.ticket]));});
await check('resident can close completed ticket',async()=>{await db.query("update public.tickets set status='closed' where id=$1",[ids.ticket]);});
await check('guest cannot read private resident data',async()=>{await asUser(null);await assert.rejects(db.query('select * from public.resident_addresses'));});
await db.exec('reset role');
await db.query("insert into public.profiles(id,company_id,role,first_name,email) values($1,$2,'worker','Other','other@test.local')",[ids.other,ids.company2]);
await check('other company cannot read tickets or resident addresses',async()=>{await asUser(ids.other,'other@test.local');assert.equal((await db.query('select * from public.tickets')).rows.length,0);assert.equal((await db.query('select * from public.resident_addresses')).rows.length,0);});
await check('other company cannot claim a ticket by guessing its ID',async()=>{await assert.rejects(db.query("select public.servicepro_transition_ticket($1,false,'','{}')",[ids.ticket]));});
await check('worker cannot edit own salary',async()=>{await asUser(ids.worker,workerEmail);const result=await db.query('update public.worker_payroll set monthly_salary=999999999 where profile_id=auth.uid() returning monthly_salary');assert.equal(result.rows.length,0);});
await db.exec('reset role');
await db.query("update public.companies set join_password='47422104' where id=$1",[ids.company]);
await check('shared code validates only the selected active organization',async()=>{
 await asUser(null);
 assert.equal((await db.query("select public.servicepro_check_company_code($1,'47422104') ok",[ids.company])).rows[0].ok,true);
 assert.equal((await db.query("select public.servicepro_check_company_code($1,'wrong') ok",[ids.company])).rows[0].ok,false);
 assert.equal((await db.query("select public.servicepro_check_company_code($1,'47422104') ok",[ids.company2])).rows[0].ok,false);
});
for (const [i,role] of ['director','admin','worker'].entries()) {
 const userId='00000000-0000-0000-0000-00000000000'+(i+5);
 const first='Shared'+i;const last='Staff';
 const email='staff_'+(await import('node:crypto')).createHash('sha256').update(ids.company+'|'+first.toLowerCase()+'|staff').digest('hex').slice(0,48)+'@servicepro.local';
 await db.exec('reset role');await db.query('insert into auth.users values($1)',[userId]);await asUser(userId,email);
 await check('shared code enrolls '+role,async()=>{
  await db.query("select public.servicepro_join_company_staff($1,$2,'47422104',$3,$4,'Electrician','uz')",[ids.company,role,first,last]);
  const r=await db.query('select role,company_id from public.profiles where id=auth.uid()');assert.equal(r.rows[0].role,role);assert.equal(r.rows[0].company_id,ids.company);
 });
 if(role==='worker') {
  await check('shared code cannot promote an existing worker',async()=>{await assert.rejects(db.query("select public.servicepro_join_company_staff($1,'director','47422104',$2,$3,'Electrician','uz')",[ids.company,first,last]));});
  await check('shared code never grants super admin',async()=>{await assert.rejects(db.query("select public.servicepro_join_company_staff($1,'super_admin','47422104',$2,$3,'Electrician','uz')",[ids.company,first,last]));});
  await check('shared enrollment retry preserves existing profile',async()=>{await db.query("select public.servicepro_join_company_staff($1,'worker','47422104',$2,$3,'Changed','uz')",[ids.company,first,last]);assert.equal((await db.query('select job_title from public.profiles where id=auth.uid()')).rows[0].job_title,'Electrician');});
 }
}
await db.exec('reset role');
for (const name of ['chat_rooms','chat_room_members','chat_messages','scheduled_notifications','device_tokens']) {
 const match=original.match(new RegExp('create table if not exists public\\.'+name+' \\([\\s\\S]*?\\n\\);'));
 assert.ok(match,'table '+name); await db.exec(match[0]);
}
await db.exec(`alter table public.notifications add column if not exists chat_room_id uuid references public.chat_rooms(id);
alter table public.notifications add column if not exists chat_message_id uuid references public.chat_messages(id);
grant all on public.chat_messages,public.chat_rooms,public.chat_room_members to authenticated;
alter table public.chat_messages enable row level security;
`);
const access=original.slice(original.indexOf('create or replace function public.chat_can_access_room'),original.indexOf('create or replace function public.chat_can_manage_room'));
await db.exec(access);
await db.exec(`create policy "messages read room" on public.chat_messages for select to authenticated using(public.chat_can_access_room(room_id));`);
await db.exec(fs.readFileSync(root+'/supabase/migrations/20261010045723_ticket_chat_notification_reliability.sql','utf8'));
const request='30000000-0000-0000-0000-000000000001';
let ticket;
await check('profile ticket stores authoritative contact snapshot',async()=>{
 await asUser(ids.resident,residentEmail);
 ticket=(await db.query("select (public.servicepro_create_profile_ticket($1,'Leaking pipe')).*",[request])).rows[0];
 assert.equal(ticket.requester_snapshot.first_name,'Ali');assert.equal(ticket.requester_snapshot.phone,'998901234567');
 assert.equal(ticket.address_text,'Mahalla, Street, 10');assert.equal(ticket.apartment_number,'');
});
await check('retry returns same ticket without duplicate event',async()=>{
 const retry=(await db.query('select (public.servicepro_create_profile_ticket($1,$2)).*',[request,'Leaking pipe'])).rows[0];assert.equal(retry.id,ticket.id);
 await db.exec('reset role');const q=await db.query('select count(*)::int n from public.tickets where request_id=$1',[request]);assert.equal(q.rows[0].n,1);
 const n=await db.query('select count(*)::int n from public.notifications where ticket_id=$1 and profile_id=$2',[ticket.id,ids.resident]);assert.equal(n.rows[0].n,1);
});
await check('anonymous ticket submission denied',async()=>{await asUser(null);await assert.rejects(db.query("select public.servicepro_create_profile_ticket($1,'x')",[request]));});
await db.exec('reset role');
const room='40000000-0000-0000-0000-000000000001';const room2='40000000-0000-0000-0000-000000000002';
await db.query("insert into public.chat_rooms(id,company_id,type,title) values($1,$2,'group','Group'),($3,$4,'group','Other')",[room,ids.company,room2,ids.company2]);
const message=(await db.query("insert into public.chat_messages(room_id,sender_id,text) values($1,$2,'Hello') returning id",[room,ids.resident])).rows[0].id;
await check('reaction set/retry/remove persists without duplicate',async()=>{
 await asUser(ids.worker,workerEmail);
 for(let i=0;i<2;i++) await db.query("select public.servicepro_set_reaction($1,$2,'👍')",[message,room]);
 assert.equal((await db.query('select count(*)::int n from public.chat_reactions')).rows[0].n,1);
 await db.query("select public.servicepro_set_reaction($1,$2,'❤️')",[message,room]);
 assert.equal((await db.query('select emoji from public.chat_reactions')).rows[0].emoji,'❤️');
 await db.query('select public.servicepro_set_reaction($1,$2,null)',[message,room]);
 assert.equal((await db.query('select count(*)::int n from public.chat_reactions')).rows[0].n,0);
});
await check('other organization cannot react or see reactions',async()=>{
 await asUser(ids.other,'other@test.local');await assert.rejects(db.query("select public.servicepro_set_reaction($1,$2,'👍')",[message,room]));
 assert.equal((await db.query('select count(*)::int n from public.chat_reactions')).rows[0].n,0);
});
await check('reaction cannot claim a different room',async()=>{
 await asUser(ids.worker,workerEmail);await assert.rejects(db.query("select public.servicepro_set_reaction($1,$2,'👍')",[message,room2]));
});
await check('chat settings isolated to owner',async()=>{
 await asUser(ids.worker,workerEmail);await db.query("insert into public.chat_preferences(room_id,profile_id,wallpaper) values($1,$2,'blue')",[room,ids.worker]);
 await asUser(ids.resident,residentEmail);assert.equal((await db.query('select count(*)::int n from public.chat_preferences')).rows[0].n,0);
 await assert.rejects(db.query("insert into public.chat_preferences(room_id,profile_id) values($1,$2)",[room,ids.worker]));
});
await check('authenticated users cannot claim push jobs',async()=>{await assert.rejects(db.query('select public.servicepro_claim_push_jobs(10)'));});
await db.exec('reset role');
await check('outbox has durable ticket and chat events',async()=>{assert.ok((await db.query('select count(*)::int n from servicepro_private.push_jobs')).rows[0].n>1);});
await check('leased jobs not claimed twice and wrong lease cannot acknowledge',async()=>{
 const jobs=(await db.query('select public.servicepro_claim_push_jobs(50) jobs')).rows[0].jobs;assert.ok(jobs.length);
 assert.equal((await db.query('select public.servicepro_claim_push_jobs(50) jobs')).rows[0].jobs.length,0);
 const job=jobs[0];await db.query("select public.servicepro_finish_push_job($1,gen_random_uuid(),true,'{}','')",[job.id]);
 assert.equal((await db.query('select delivered_at from servicepro_private.push_jobs where notification_id=$1',[job.id])).rows[0].delivered_at,null);
 await db.query("select public.servicepro_finish_push_job($1,$2,true,'{}','')",[job.id,job.lease_token]);
 assert.ok((await db.query('select delivered_at from servicepro_private.push_jobs where notification_id=$1',[job.id])).rows[0].delivered_at);
});
await check('scheduled notification enqueued once per local date',async()=>{
 await db.query("insert into public.scheduled_notifications(title,body,send_time) values('Reminder','Body','00:00')");
 assert.equal((await db.query('select public.servicepro_enqueue_schedules() n')).rows[0].n,1);
 assert.equal((await db.query('select public.servicepro_enqueue_schedules() n')).rows[0].n,0);
});

await check('ticket contact snapshot cannot be rewritten',async()=>{
 await db.exec('reset role');await assert.rejects(db.query("update public.tickets set requester_snapshot='{}'::jsonb where id=$1",[ticket.id]));
});
await check('token transfer deactivates previous account without deleting history',async()=>{
 const token='test-device-token-not-a-real-fcm-token-12345';
 await asUser(ids.resident,residentEmail);await db.query("select public.servicepro_register_device($1,'android')",[token]);
 await asUser(ids.worker,workerEmail);await db.query("select public.servicepro_register_device($1,'android')",[token]);
 await db.exec('reset role');const rows=(await db.query('select profile_id,is_active from public.device_tokens where token=$1',[token])).rows;
 assert.equal(rows.length,2);assert.equal(rows.find(r=>r.profile_id===ids.resident).is_active,false);assert.equal(rows.find(r=>r.profile_id===ids.worker).is_active,true);
});
await check('notification routing identity cannot be rewritten',async()=>{
 await asUser(ids.resident,residentEmail);
 await db.exec('reset role');
 await assert.rejects(db.query('update public.notifications set profile_id=$1 where ticket_id=$2',[ids.other,ticket.id]));
});
await check('contact update changes future profile but preserves submitted snapshot',async()=>{
 await asUser(ids.resident,residentEmail);
 await db.query("select public.servicepro_save_ticket_contact('Ali','Vali','998901234567','New Mahalla','New Street','20')");
 await db.exec('reset role');
 assert.equal((await db.query('select requester_snapshot from public.tickets where id=$1',[ticket.id])).rows[0].requester_snapshot.house_number,'10');
});
await db.exec('reset role');
await db.exec("alter table public.chat_rooms add column pinned_message_id uuid references public.chat_messages(id) on delete set null");
const readsDdl=original.match(/create table if not exists public\.chat_message_reads \([\s\S]*?\n\);/)[0];
await db.exec(readsDdl);
await db.exec(fs.readFileSync(root+'/supabase/migrations/20261013115038_workforce_notifications.sql','utf8'));
const msg2='50000000-0000-0000-0000-000000000002';
await db.query("insert into public.chat_messages(id,room_id,sender_id,text) values($1,$2,$3,'Other room')",[msg2,room2,ids.other]);
const manager='00000000-0000-0000-0000-000000000099';
await db.query('insert into auth.users values($1)',[manager]);
await db.query("insert into public.profiles(id,company_id,role,first_name) values($1,$2,'director','Manager')",[manager,ids.company]);
await check('manager assigns worker and completion credits worker, actor separate',async()=>{
 await asUser(manager);
 const accepted=(await db.query("select (public.servicepro_transition_ticket_worker($1,false,'','{}',$2)).*",[ticket.id,ids.worker])).rows[0];
 assert.equal(accepted.accepted_by,ids.worker);assert.equal(accepted.accepted_by_actor,manager);
 const done=(await db.query("select (public.servicepro_transition_ticket_worker($1,true,'Fixed',ARRAY['photo'],$2)).*",[ticket.id,ids.worker])).rows[0];
 assert.equal(done.completed_by,ids.worker);assert.equal(done.completed_by_actor,manager);assert.ok(done.completed_at);
});
await check('lost completion response retries without duplicate event',async()=>{
 await db.query("select public.servicepro_transition_ticket_worker($1,true,'Fixed',ARRAY['photo'],$2)",[ticket.id,ids.worker]);
 await db.exec('reset role');
 const count=(await db.query("select count(*)::int n from public.notifications where profile_id=$1 and event_key=$2",[ids.worker,'ticket:'+ticket.id+':completed'])).rows[0].n;
 assert.equal(count,1);
});
await check('resident review credits worker and is idempotent',async()=>{
 await asUser(ids.resident,residentEmail);
 await db.query("select public.servicepro_rate_work($1,5,'Good work')",[ticket.id]);
 await db.query("select public.servicepro_rate_work($1,5,'Good work')",[ticket.id]);
 await db.exec('reset role');
 const row=(await db.query('select * from public.worker_ratings where ticket_id=$1',[ticket.id])).rows[0];
 assert.equal(row.worker_id,ids.worker);assert.equal(row.score,5);assert.equal(row.comment,'Good work');
 assert.equal((await db.query('select count(*)::int n from public.worker_ratings where ticket_id=$1',[ticket.id])).rows[0].n,1);
});
await check('other resident cannot rate another company ticket',async()=>{
 await asUser(ids.other,'other@test.local');
 await assert.rejects(db.query("select public.servicepro_rate_work($1,1,'Bad')",[ticket.id]));
});
await check('manager salary write isolated to own company',async()=>{
 await asUser(manager);await db.query("select public.servicepro_set_worker_details($1,'Plumber',2000000)",[ids.worker]);
 await assert.rejects(db.query("select public.servicepro_set_worker_details($1,'Plumber',-1)",[ids.worker]));
 const otherWorker='00000000-0000-0000-0000-000000000098';
 await db.exec('reset role');await db.query('insert into auth.users values($1)',[otherWorker]);
 await db.query("insert into public.profiles(id,company_id,role,first_name) values($1,$2,'worker','OtherWorker')",[otherWorker,ids.company2]);
 await asUser(manager);await assert.rejects(db.query("select public.servicepro_set_worker_details($1,'Electrician',100)",[otherWorker]));
});
await check('ranking visible to residents without salaries',async()=>{
 await asUser(ids.resident,residentEmail);
 const team=(await db.query('select public.servicepro_team_directory() team')).rows[0].team;
 const worker=team.find(p=>p.id===ids.worker);assert.equal(worker.monthly_salary,null);assert.equal(worker.star_total,10);assert.equal(worker.rating_count,2);
});
await check('cleanup rejected for manager, cross-room selection rejected for super',async()=>{
 await asUser(manager);await assert.rejects(db.query("select public.servicepro_cleanup_company($1,'tickets',null)",[ids.company]));
 await asUser(ids.super,'admin@test.local');
 await assert.rejects(db.query("select public.servicepro_delete_chat_messages($1,$2,ARRAY[$3]::uuid[])",[ids.company,room,msg2]));
});
await check('selective message deletion keeps other organization history',async()=>{
 await asUser(ids.super,'admin@test.local');
 await db.query("select public.servicepro_delete_chat_messages($1,$2,ARRAY[$3]::uuid[])",[ids.company,room,message]);
 await db.exec('reset role');assert.equal((await db.query('select count(*)::int n from public.chat_messages where id=$1',[message])).rows[0].n,0);
 assert.equal((await db.query('select count(*)::int n from public.chat_messages where id=$1',[msg2])).rows[0].n,1);
});
await check('organization cleanup does not delete other organization or profiles',async()=>{
 await asUser(ids.super,'admin@test.local');await db.query("select public.servicepro_cleanup_company($1,'chats',null)",[ids.company]);
 await db.exec('reset role');assert.equal((await db.query('select count(*)::int n from public.chat_messages where id=$1',[msg2])).rows[0].n,1);
 assert.ok((await db.query('select count(*)::int n from public.profiles')).rows[0].n>4);
});
await check('completed tickets excluded from twice daily reminders',async()=>{
 await db.exec('reset role');await db.query('select public.servicepro_enqueue_ticket_reminders()');
 assert.equal((await db.query("select count(*)::int n from public.notifications where ticket_id=$1 and notification_type='ticket_reminder'",[ticket.id])).rows[0].n,0);
});
await check('uncompleted resident requests remind managers and assigned worker once per slot',async()=>{
 await db.exec('reset role');await asUser(ids.resident,residentEmail);
 const next=(await db.query("select (public.servicepro_create_profile_ticket(gen_random_uuid(),'Pending')).*")).rows[0];
 await asUser(manager);await db.query("select public.servicepro_transition_ticket_worker($1,false,'','{}',$2)",[next.id,ids.worker]);
 await db.exec('reset role');
 await db.query("update public.tickets set created_at=now()-interval '1 day' where id=$1",[next.id]);
 await db.query('select public.servicepro_enqueue_ticket_reminders()');
 const before=(await db.query("select count(*)::int n from public.notifications where ticket_id=$1 and notification_type='ticket_reminder'",[next.id])).rows[0].n;
 await db.query('select public.servicepro_enqueue_ticket_reminders()');
 const after=(await db.query("select count(*)::int n from public.notifications where ticket_id=$1 and notification_type='ticket_reminder'",[next.id])).rows[0].n;
 assert.equal(after,before);
 const hour=(await db.query("select extract(hour from now() at time zone 'Asia/Tashkent')::int h")).rows[0].h;
 if(hour>=9){assert.ok(before>=2);assert.equal((await db.query("select count(*)::int n from public.notifications where ticket_id=$1 and notification_type='ticket_reminder' and profile_id=$2",[next.id,ids.worker])).rows[0].n,1);}
});
console.log(`${tests} integration checks passed`);await db.close();
