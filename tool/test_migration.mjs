import { PGlite } from '@electric-sql/pglite';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
const db = new PGlite();
const root = fileURLToPath(new URL('..', import.meta.url)).replace(/[\\/]$/, '');
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
console.log(`${tests} backend integration checks passed`);
await db.close();
