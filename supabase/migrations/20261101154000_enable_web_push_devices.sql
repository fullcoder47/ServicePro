-- Allow authenticated ServicePro web/PWA installations to register FCM tokens.
-- Android and native iOS keep their existing platform names and behavior.
create or replace function servicepro_private.register_device(
  p_token text, p_platform text
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  p public.profiles%rowtype;
begin
  if auth.uid() is null
     or coalesce(length(p_token), 0) < 20
     or length(p_token) > 4096
     or p_platform not in ('android', 'ios', 'web') then
    raise exception 'invalid_device';
  end if;

  select * into p from public.profiles where id = auth.uid();
  if not found then raise exception 'profile_required'; end if;

  update public.device_tokens
  set is_active = false
  where token = p_token and profile_id <> p.id;

  insert into public.device_tokens(
    profile_id, company_id, token, platform, is_active, updated_at
  ) values (p.id, p.company_id, p_token, p_platform, true, now())
  on conflict (profile_id, token) do update
  set company_id = excluded.company_id,
      platform = excluded.platform,
      is_active = true,
      updated_at = now();
end $$;

-- Preserve the authenticated-only entry point; never grant to public/anon.
create or replace function public.servicepro_register_device(
  p_token text, p_platform text
) returns void
language sql security invoker set search_path = '' as $$
  select servicepro_private.register_device(p_token, p_platform)
$$;

revoke all on function
  servicepro_private.register_device(text, text),
  public.servicepro_register_device(text, text)
from public, anon;
grant execute on function
  servicepro_private.register_device(text, text),
  public.servicepro_register_device(text, text)
to authenticated;
