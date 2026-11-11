-- Use only after the worker and the new migration are installed.
-- Create the matching secret in Vault BEFORE running this file.
begin;
do $$
declare legacy bigint;
begin
 if not exists(select 1 from vault.secrets where name='notification_job_secret') then
  raise exception 'Create notification_job_secret in Vault first (same value as Edge NOTIFICATION_JOB_SECRET).';
 end if;
 for legacy in select jobid from cron.job where jobname='scheduled-push-runner-every-minute' loop
  perform cron.alter_job(legacy,active:=false);
 end loop;
end $$;
select cron.schedule('servicepro-notification-worker-v3','* * * * *',$job$
 select net.http_post(
  url:='https://inbqjyypfpfqnpcjqkqn.supabase.co/functions/v1/notification-worker',
  headers:=jsonb_build_object('Content-Type','application/json',
    'x-job-secret',(select decrypted_secret from vault.decrypted_secrets where name='notification_job_secret' limit 1)),
  body:='{}'::jsonb,timeout_milliseconds:=15000
 );
$job$);
commit;
