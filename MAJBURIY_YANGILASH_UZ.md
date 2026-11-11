# ServicePro — majburiy Android yangilash

## Ishga tushirish

1. Supabase SQL Editor'da `supabase/SERVICEPRO_FORCE_UPDATE_SETUP.sql` faylini bir marta bajaring. Boshlang'ich `min_build=15` — hech kimni bloklamaydi.
2. Android Studio terminalida `flutter pub get`, `flutter analyze`, `flutter run` bajaring; chat, login, billing va ekranlar to'g'ri ishlashini tekshiring.
3. Google Play uchun `flutter build appbundle --release` bajaring. `pubspec.yaml` versiyasi **1.0.4+17** qilib qo'yildi. Agar +17 avval Play Console'ga yuklangan bo'lsa, build raqamini Play Console'dagi eng katta koddan yuqoriga o'zgartiring.
4. Yangi versiya Play Marketda hamma uchun ochilganini tekshiring.
5. Keyingi yangilanishlarda Supabase SQL Editor'da `min_build`ni oshirib, shu tekshiruv kodi mavjud eski buildlarni to'sishingiz mumkin:

```sql
update public.servicepro_update_policy
set min_build = 17, updated_at = now()
where platform = 'android';
```

**Diqqat:** +17 build haqiqatan Google Play'da chiqmaguncha 17 qilib qo'ymang. Aks holda +16 ishlatayotganlar ham ilovaga kira olmay qoladi.

## Qanday ishlaydi?

- Ilova ochilganda va Play Marketdan qaytganda Android `versionCode` Supabase'dagi `min_build` bilan taqqoslanadi.
- Qurilmadagi build kichik bo'lsa, barcha sahifalar ustida yopilmaydigan yangilash ekrani chiqadi. “Play Marketda yangilash” tugmasi Google Play'dagi ServicePro sahifasini ochadi.
- Oxirgi tekshirilgan minimum qurilmada saqlanadi. Internet uzilganda oldin ma'lum bo'lgan cheklov saqlanadi. Birinchi marta internet bo'lmasa, tekshiruv server bilan aloqa tiklanganda ishlaydi.
- Windows/iOS uchun cheklov yo'q. Supabase'da mavjud servislar va ma'lumotlar o'zgartirilmaydi.

**Muhim:** yangilash kodi hozir bo'lmagan allaqachon o'rnatilgan juda eski APK'larni masofadan shu usulda to'sib bo'lmaydi. Faqat ushbu kod o'rnatilgan versiyalardan boshlab ishlaydi. Google Play ham foydalanuvchi roziligisiz APK'ni o'rnatib bermaydi.
