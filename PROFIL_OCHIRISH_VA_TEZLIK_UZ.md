# ServicePro — profilni o‘chirish va tezlik tuzatishlari

## 1. Serverda ishga tushirish (majburiy)

1. Supabase SQL Editor'da **`supabase/PROFILE_DELETE_SETUP.sql`** faylini bir marta ishga tushiring. Bu faqat o‘z Storage fayllarini aniqlash funksiyasini yaratadi; hech qanday profilni o‘chirmaydi.
2. Supabase Dashboard → Edge Functions → yangi **`delete-my-account`** funksiyasini yarating. Uning kodini **`supabase/functions/delete-my-account/index.ts`** faylidan joylashtirib Deploy qiling. **Verify JWT yoqilgan bo‘lsin.** Service-role kaliti faqat Supabase serverida turishi kerak, Flutter dasturiga kiritilmasin.
3. Agar Supabase Data API’da public RPC mavjud bo‘lmasa, `servicepro_my_owned_storage_objects` funksiyasi Data API orqali chaqirilishini tekshiring.
4. Avval **alohida test aholisi profili** bilan sinang. Haqiqiy aholi akkauntlari bilan test qilmang.

## 2. Profilni o‘chirish oqibati

- Profil sahifasining eng pastida “Ilovani tark etish” ostida “Profilni o‘chirish” tugmasi bor.
- Aholi foydalanuvchisi ogohlantirish va majburiy tasdiq belgisini ko‘radi. Tasdiqdan keyin server aynan joriy JWT egasining akkauntini o‘chiradi; ilova boshqa foydalanuvchi ID sini yubormaydi.
- `auth.users` va unga `on delete cascade` orqali bog‘langan `profiles`, shu foydalanuvchining arizalari va chat yozishmalari o‘chiriladi. Uning Storage fayllari ham olib tashlanadi; amalni ortga qaytarib bo‘lmaydi.
- Direktor, Admin, Ishchi va Super Admin profillari avtomatik o‘chirilmaydi. Ular tashkilot vazifalari, arizalar va kompaniya FKlari bilan bog‘langan; vazifalarni avval xavfsiz o‘tkazish kerak. Bunda boshqa foydalanuvchi yoki kompaniya ma’lumoti tasodifan o‘chmaydi.
- Server funksiyasi yo‘q yoki xato qaytarsa, ilova profilni o‘chirilgan deb ko‘rsatmaydi.

## 3. Tezlik va barqarorlik

- 1 soniyalik zaxira to‘liq ma’lumot yangilash so‘rovlari **15 soniya** oraliqqa o‘tkazildi. Realtime tinglovchilari saqlangan, xabarlar imkon qadar darhol keladi.
- Internetni tekshirish 2 soniyadan **10 soniya**ga o‘tkazildi va ustma-ust parallel tekshiruvlarga chek qo‘yildi.
- Akkaunt almashganda eski tarmoq javoblari yangi profil ma’lumotlari ustiga yozilmasligi uchun himoya qo‘shildi.
- Chiqishda chat keshi tozalanadi.

## 4. Android Studio sinovi

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

Profil o‘chirish, chat, arizalar, tashkilot login, Super Admin, billing blokirovkasi, push bildirishnomalar va Windows ekranlarini sinang. Ushbu muhitda Flutter SDK yo‘qligi uchun bu testlar avtomatik bajarilmadi.

`pubspec.yaml` versiyasi **1.0.4+17**. Play Console’da +17 allaqachon ishlatilgan bo‘lsa, `versionCode` ni oshiring. Eski Android buildlarni majburiy yangilash moduli oldingi versiyadan saqlangan.
