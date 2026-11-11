# ServicePro — Super Admin billing bloklash (Android va Windows)

Maqsad: Super Admin `Billing` ichida tashkilotni **Bloklash** tugmasi bilan bloklasa,
shu tashkilotning direktor, admin va ishchilarida barcha ekranlar xiralashadi;
modal va navigatsiya tugmalari ham ishlamaydi. Aholi va Super Admin bloklanmaydi.
**Blokdan chiqarish** avvalgi obuna holatini qaytaradi (muddati tugagan bo‘lsa `expired`).

## Majburiy 1-qadam: Supabase SQL

Supabase Dashboard -> SQL Editor -> **New query** ichida faqat quyidagi migratsiya faylini
**bir marta** ishga tushiring:

`supabase/migrations/20261016181500_billing_super_admin_lock.sql`

Bu SQL mavjud billing jadvalini qayta yaratmaydi, ma’lumotlarni o‘chirmaydi;
`status_before_block` maydonini, `set_company_billing_block` RPC va bloklash auditi
hamda biznes jadvallaridagi yozish amallari uchun server himoyasini qo‘shadi.

**ESLATMA:** `supabase/servicepro_schema.sql` faylini boshqatdan to‘liq run qilmang:
eski siyosatlar yangi himoya siyosatlariga ta’sir qilishi mumkin.

## 2-qadam: loyihani ishga tushirish

Avval asl ServicePro papkasi uchun backup yarating. Patch ZIP ichida atigi 5 ta
kod/migratsiya fayli va test/yo‘riqnoma bor. `lib` va `supabase` kataloglarini
loyiha ildiziga birlashtirib, ustidan yozing. Hech bir paket yoki `.env` o‘zgartirilmagan.

```powershell
cd "C:\Users\saman\OneDrive\Desktop\ServicePro"
flutter pub get
flutter analyze
flutter test test/billing/billing_lock_test.dart
$env:CMAKE_POLICY_VERSION_MINIMUM = "3.5"
flutter run -d windows
```

Android'da `flutter run -d <android-device-id>` orqali sinab ko‘ring.

## Nazorat sinovi

1. Direktor va ishchi hisoblari ochiq turgan paytda Super Admin billingdan bitta tashkilotni bloklasin.
2. Ilova Realtime orqali yoki 12 soniyalik tekshiruvda bloklansin. Internet uzilishi blokni o‘chirmaydi.
3. Ekran va barcha bosiladigan elementlar nofaol bo‘lsin; faqat `Holatni tekshirish` va `Hisobdan chiqish` tugmalari ishlasin.
4. Super Admin `Blokdan chiqarish`ni bosgach, barcha oynalar yana ishlasin.
5. Boshqa kompaniya va aholi foydalanuvchilarining faoliyati o‘zgarmasin.

## Texnik cheklovlar

- Blok **faqat Super Admin qo‘lda `blocked` statusiga o‘tkazganda** qo‘llanadi;
  `expired` avtomatik bloklanmaydi.
- Server triggerlari asosiy biznes jadvallariga *yozishni* to‘xtatadi. Eski SELECT
  RLS siyosatlari saqlangan; REST orqali ma’lumotlarni *o‘qishni* global o‘chirish
  va Supabase Storage ruxsatlarini cheklash alohida audit talab qiladi.
- Ochiq Windows/Android ilovalarida o‘zgarish real vaqtda yetib borishi uchun
  Supabase Realtime'da `public.subscriptions` jadvali replikatsiyasini yoqish mumkin;
  bu yoqilmagan bo‘lsa 12 soniyalik polling ishlaydi.
- Admin bloklangan tashkilotga to‘lov qo‘shsa, blok avtomatik yechilmaydi.
- Flutter SDK bu tayyorlash muhitida mavjud emas: real compile/test natijalari
  mahalliy kompyuteringizda tekshirilishi kerak.
