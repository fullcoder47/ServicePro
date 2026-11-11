-- One-time SQL Editor setup for the delete-my-account Edge Function.
-- Read-only, JWT-scoped listing. No live data is changed by this setup.

create or replace function public.servicepro_my_owned_storage_objects()
returns table(bucket_id text, object_name text)
language sql
security definer
set search_path = ''
as $$
  select objects.bucket_id::text, objects.name::text
  from storage.objects as objects
  where objects.owner_id = (select auth.uid())::text
    and exists (
      select 1 from public.profiles as profile
      where profile.id = (select auth.uid())
        and profile.role = 'user'
    );
$$;

revoke all on function public.servicepro_my_owned_storage_objects()
  from public, anon, authenticated;
grant execute on function public.servicepro_my_owned_storage_objects()
  to authenticated;
