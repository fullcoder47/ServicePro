# ServicePro — Kirilgan qurilmalar va xavfsizlik

## Nima qo‘shildi?

- Profil → Sozlanmalar → **Kirilgan qurilmalar va xavfsizlik**.
- Har bir sessiya: qurilma nomi/platforma, kirish va oxirgi faollik vaqti,
  IP manzil, ilova versiyasi, hozirgi qurilma belgisi, mavjud bo‘lsa MFA darajasi.
- O‘z qurilmasining nomini o‘zgartirish.
- Bir dona **boshqa** qurilmaning sessiyasini bekor qilish.
- **Boshqa barcha qurilmalar**dan chiqish (joriy qurilma qoladi).
- **Barcha qurilmalar**dan chiqish (joriy qurilma ham chiqadi).
- Har 3 daqiqada ilova ochiq bo‘lgan qurilmaning oxirgi faolligi yangilanadi.
- Server sessiyalarni faqat `auth.uid()` bo‘yicha qaytaradi; ilova `auth.sessions`
  yoki `service_role` kalitiga to‘g‘ridan-to‘g‘ri kira olmaydi.
- Bittalab chiqarish holatlari alohida xavfsizlik jurnalida saqlanadi.

## O‘rnatish tartibi

1. Hozirgi ishlab turgan Flutter loyihasini va Supabase bazasini zaxiralang.
2. Avval test/staging Supabase loyihasida
   `supabase/SESSION_DEVICES_SECURITY_SETUP.sql` ni SQL Editor orqali ishga
   tushiring va pastdagi senariylarni sinang.
3. Test yaxshi bo‘lgach, shu SQLni ishlab turgan Supabase loyihasida o‘rnating.
4. Flutter kodidagi yangi fayllar bilan `flutter pub get`, `flutter analyze`,
   Android/Windows/Web build va ikki real qurilmada sinov qiling.
5. Keyin yangi versiyani Play Market / Microsoft Store / Hostingga chiqaring.

Bu arxivning asosi 2026-11-06 dagi nusxa. O‘sha kundan keyin boshqa kod
o‘zgarishlari bo‘lgan bo‘lsa, ularni yo‘qotmaslik uchun alohida o‘zgartirilgan
fayllarni loyihaning so‘nggi versiyasiga qo‘shib chiqing.

## Majburiy testlar

1. A va B ikki xil akkaunt bilan, har birida kamida ikkita sessiya yarating.
2. A foydalanuvchi B sessiyalarini ko‘ra olmasligi va o‘chira olmasligini tekshiring.
3. A hisobida BIR dona boshqa qurilmani yoping: joriy qurilma ishlashda qolsin.
4. A hisobida barcha BOSHQA qurilmalarni yoping: joriy qurilma qolsin.
5. A hisobida barcha qurilmalardan chiqing: joriy qurilma ham login oynasiga qaytsin.
6. Eski app versiyasidan yangi SQL bilan chat yuborish hamon ishlashini tekshiring.
7. Windows, Android va PWA orqali kirishni, qurilma nomini o‘zgartirishni sinang.
8. Internet uzilganda ekran xatoni tushunarli ko‘rsatishini tekshiring.
9. Supabase `auth.sessions` dagi sessiya o‘chirilgach, unga bog‘langan
   `auth.refresh_tokens` yozuvlari ham o‘chishini tekshiring.

## Muhim xavfsizlik chegaralari

- Supabase Flutter Auth ning `SignOutScope.others` / `global` amallari
  rasmiy APIga tayanadi. Bittalab chiqarish uchun yozilgan RPC esa hozirgi
  Supabase GoTrue sxemasidagi `auth.sessions` jadvalini o‘chiradi, bunga
  `auth.refresh_tokens.session_id` FOREIGN KEY `ON DELETE CASCADE` bog‘langan.
  Bu boshqariladigan auth sxemasiga tegadi; ishlab turgan bazada faqat staging
  testidan so‘ng ishlating. Supabase sxemasi yangilansa, qayta audit qilish zarur.
- Eskidan berilgan JWT Access Token o‘z `exp` muddatigacha boshqa ayrim
  so‘rovlarda ishlashi mumkin. Chat INSERT/UPDATEga sessiya-mavjudlik guard
  qo‘shilgan; boshqa muhim RPC/RLS yo‘llarini ham alohida qattiqlashtirish kerak.
- Avvalgi qurilmalarning aniq modeli aniqlanmasligi mumkin, chunki avvalgi
  Auth sessiyalarida ko‘pincha faqat `Dart/3.12` user-agent saqlangan. Yangi
  sessiyalar platformasi va nomi ro‘yxatga olinadi.
- IP manzilga qarab inson yoki uning aniq geografik manzilini aniqlab bo‘lmaydi.
- Bu o‘zgarish **super admin MFA/TOTP talabini** hali to‘liq joriy qilmaydi.
  Super admin akkauntiga MFA va serverda `aal2` tekshiruvi keyingi majburiy
  xavfsizlik bosqichidir.
- Hech qanday ishlab turgan sessiya bu kod arxivi yaratilayotganda bekor qilinmadi.

## Kodda o‘zgartirilgan joylar

- `lib/data/app_state.dart` — sessiyalarni muntazam ro‘yxatga olish, global logout.
- `lib/data/session_devices_repository.dart` — qurilmalar API va lokal identifikator.
- `lib/features/profile/profile_page.dart` — profilga kirish tugmasi.
- `lib/features/profile/devices_page.dart` — yangi adaptiv sahifa.
- `supabase/SESSION_DEVICES_SECURITY_SETUP.sql` — server funksiyalari va audit.

Flutter SDK mavjud bo‘lmagan muhitda build/analyzer sinovi o‘tkazilmadi.
Shu bois ilovani ommaga chiqarmasdan oldin yuqoridagi tekshiruvlardan o‘ting.
