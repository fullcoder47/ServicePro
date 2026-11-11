-- Run only after migration, worker deployment and matching Vault/Edge secrets.
-- Inspect existing jobs first; do not leave legacy scheduled push jobs active.
select jobid, jobname, schedule, active from cron.job;
select cron.schedule(
  'servicepro-notification-worker-v2',
  '* * * * *',
  $job$
    select net.http_post(
      url := 'https://inbqjyypfpfqnpcjqkqn.supabase.co/functions/v1/notification-worker',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-job-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'notification_job_secret')
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 15000
    );
  $job$
);
