-- ServicePro: majburiy Android yangilash uchun ALOHIDA sozlama.
-- Supabase SQL Editor'da FAQAT BIR MARTA ishga tushiring.
-- Eski app_settings, chat, billing va boshqa jadvallar o'zgarmaydi.

create table if not exists public.servicepro_update_policy (
  platform text primary key check (platform in ('android')),
  min_build integer not null default 0 check (min_build >= 0),
  updated_at timestamptz not null default now()
);

alter table public.servicepro_update_policy enable row level security;
revoke all on table public.servicepro_update_policy from public, anon, authenticated;
grant select on table public.servicepro_update_policy to anon, authenticated;

drop policy if exists "Anyone can read the Android update requirement"
  on public.servicepro_update_policy;
create policy "Anyone can read the Android update requirement"
  on public.servicepro_update_policy
  for select to anon, authenticated using (true);

-- 15 hozirgi eski build: dastlab hech kim bloklanmaydi.
-- 16-build Play'da CHIQQANDAN KEYIN minimal buildni oshirishingiz mumkin.
insert into public.servicepro_update_policy(platform, min_build)
values ('android', 15)
on conflict (platform) do nothing;

select platform, min_build, updated_at
from public.servicepro_update_policy;

-- KEYINCHALIK (faqat yangilanish Play'da tasdiqlangandan keyin):
-- update public.servicepro_update_policy
-- set min_build = 16, updated_at = now()
-- where platform = 'android';
