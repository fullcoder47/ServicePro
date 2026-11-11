# ServicePro — Mening hisobim va plastik karta (DEMO)

## Qilingan o'zgarishlar

- `lib/features/subscribers/my_account_page.dart` — aholi uchun ixcham hisob sahifasi:
  jami qarz, biriktirilgan hisoblar, manzil, biriktirish so'rovlari va demo kartalar.
- `lib/features/subscribers/demo_billing_api.dart` — kelajakdagi API uchun `BillingApi`
  kontrakti, namunaviy qarzdorlik yozuvlari, demo to'lov va karta maketlari.
- `lib/features/subscribers/billing_demo_preview_page.dart` — tashkilot uchun
  API ma'lumotlarining alohida **DEMO** ko'rinishi (3 ta uydirma abonent).
- `lib/features/subscribers/subscribers_page.dart` — faqat demo oynani ochadigan
  bitta tugma qo'shildi. Mavjud Excel import, filtr, RLS va haqiqiy abonentlar
  ro'yxati o'zgartirilmadi.
- `test/demo_billing_api_test.dart` — demo ma'lumot va kartalar uchun testlar.

## Muhim xavfsizlik chegaralari

1. Bu bank API yoki `Mening Uyim` API emas. Demo ma'lumotlar real abonentlarga
   tegishli emas va hech qanday real balansni o'zgartirmaydi.
2. Demo kartaga faqat karta turi (`UZCARD` yoki `HUMO`) va **oxirgi to'rtta raqam**
   kiritiladi. To'liq karta raqami, CVV, PIN va muddati so'ralmaydi yoki saqlanmaydi.
3. Demo kartalar faqat joriy qurilmaning `shared_preferences` xotirasida,
   profil ID bo'yicha ajratilgan holda saqlanadi. Bu haqiqiy bank kartasini
   ulashning o'rnini bosmaydi.
4. Demo to'lov 1 000 so'mlik sinov javobini qaytaradi. Haqiqiy pul yechilmaydi,
   `billing_transactions` yoki `billing_accounts`ga ma'lumot yozilmaydi.
5. Tashkilotning amaldagi abonentlar ro'yxati avvalgidek Supabase
   `billing_accounts` manbasidan keladi; demo ro'yxat unga **aralashtirilmaydi**.

## Haqiqiy API kelganda

`BillingApi` interfeysiga haqiqiy, server orqali ishlovchi adapter qo'shiladi.
Tashkilot uchun kontraktning taxminiy ma'lumotlari:

| Maydon | Mazmuni |
| --- | --- |
| `accountNumber` | Abonent hisob raqami |
| `fullName` | F.I.Sh. yoki noturar ob'ekt nomi |
| `address` | To'liq manzil |
| `type` | Aholi / Noturar |
| `balanceUzS` | Musbat — qarz; manfiy — ortiqcha to'lov |
| `monthlyChargeUzS` | Oy hisoblanmasi |
| `lastPaymentUzS` | Oxirgi to'lov summasi |
| `tariffUzS` | Amaldagi tarif |
| `area` | Xonadon yoki obyekt maydoni |
| `updatedAt` | Manbadagi so'nggi yangilanish vaqti |

Server tashqi billing API bilan ishlaganda tokenlar va maxfiy kalitlar Flutter
ilovasida bo'lmasligi kerak. So'rovlar tashkilot huquqlarini serverda tekshirsin,
foydalanuvchi esa faqat o'ziga biriktirilgan hisoblarni ko'rsin. Real plastik
karta uchun sertifikatlangan to'lov provayderi va tokenizatsiya ishlatiladi;
PAN/CVV dastur bazasiga yozilmaydi.

## O'rnatish va tekshirish

1. Avvalgi loyihangizning nusxasini saqlang. Ushbu paketdagi **o'zgargan**
   Dart fayllarni aynan o'z yo'liga joylashtiring (yoki to'liq manbani oching).
2. `flutter pub get`
3. `dart format --output=none --set-exit-if-changed lib/features/subscribers test/demo_billing_api_test.dart`
4. `flutter analyze lib/features/subscribers test/demo_billing_api_test.dart`
5. `flutter test test/demo_billing_api_test.dart`
6. Aholi profilida: balans, hisob bog'lash, manzil, demo karta qo'shish/o'chirish,
   demo to'lovni tekshiring. Tashkilot profilida: `Abonentlar` → `API ma'lumotlari
   (demo ko'rinish)` tugmasini tekshiring.

**Eslatma:** Ushbu paketda hech qanday SQL migratsiya yoki jonli bazaga yozish
amalga oshirilmagan. Haqiqiy API ulanishi alohida bosqichda tasdiqlanadi.
