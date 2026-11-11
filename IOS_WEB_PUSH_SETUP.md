# ServicePro — iPhone/iPad Web Push ishga tushirish

Bu loyiha iOS **16.4+** Home Screen PWA uchun tayyorlandi. Apple Developer
akkaunti kerak emas. Android va Windows ilovalari o'zgartirilgan web sozlamalarga
bog'liq emas. Push faqat tizimga kirgan, notification ruxsatini bergan
foydalanuvchining qurilmasiga yuboriladi.

## 1. Firebase Web App ID va Web Push kalitini kiriting

1. Firebase Console > `zayaflkalar` > Project settings > **General**.
2. **Your apps** bo'limida Web (`</>`) ilovasi mavjud bo'lmasa, yarating.
3. Web app configuration'dan **appId** (`1:...:web:...`) ni nusxalang.
4. **Cloud Messaging** > **Web Push certificates** dan key pair yarating
   (mavjud bo'lsa, public key'dan foydalaning).
5. `web/firebase-web-config.js` faylidagi `appId` va
   `serviceProVapidKey` ning PUBLIC qiymatlari ushbu paketda allaqachon
   sozlangan. Firebase loyihasi yoki Web App o'zgarsagina yangilang.
6. Boshqa ma'lumotlar `zayaflkalar` loyihasining Firebase Hosting config
   endpointidan olingan. Firebase loyihasi o'zgarsa, ularni ham yangilang.

**DIQQAT:** Firebase private key, service account JSON yoki Supabase `service_role`
kalitini `web/` papkasiga kiritmang. Faqat Firebase Web config va *public*
VAPID key kerak. Bo'sh appId/VAPID bo'lsa, web ilova ishlashda davom etadi,
lekin Push tugmasi yoqilmaydi.

## 2. Supabase SQL yangilanishi (mavjud arizalarni o'chirmaydi)

Supabase SQL Editor'da yangi migratsiyani bir marta ishlating:

`supabase/migrations/20261101154000_enable_web_push_devices.sql`

Bu faqat `servicepro_register_device` funksiyasiga `web` platformasini
qo'shadi. Eski arizalar, xabarlar va qurilma tokenlari o'chirilmaydi.
`anon` foydalanuvchilar boshqalar nomidan token ro'yxatga ololmaydi.

## 3. Push yuboruvchi Edge Function'ni yangilang

Mavjud `notification-worker`ni shu loyihadagi kod bilan deploy qiling.
U endi FCM `webpush` payloadini, bildirishnomaga bosilganda ochiladigan
ariza/chat ID'larini ham yuboradi. Oldingi Android/iOS payloadlari saqlangan.
Mavjud Cron, `NOTIFICATION_JOB_SECRET`, `FIREBASE_PROJECT_ID`,
`FIREBASE_CLIENT_EMAIL`, `FIREBASE_PRIVATE_KEY` sozlamalarini saqlang.
Ularni ko'chirmang yoki oshkor qilmang.

## 4. Web versiyani qayta build va deploy qiling

Windows PowerShell, `ServicePro` papkasida:

```powershell
flutter pub get
flutter build web --release
firebase deploy --only hosting --project zayaflkalar
```

`firebase hosting:channel:deploy servicepro` **preview** havola yaratadi:
u muddatli, foydalanuvchilarga doimiy manzil sifatida tarqatmang.
Doimiy manzil — `https://zayaflkalar.web.app/`.

## 5. iPhone'da haqiqiy test

1. iOS 16.4+ iPhone'da Safari orqali doimiy HTTPS manzilni oching.
2. Share > **Add to Home Screen** orqali ServicePro ikonkasini o'rnating.
3. Ikonkadan oching, o'z akkauntingizga kiring.
4. Yuqoridagi notification ikonkasini ochib **Yoqish** tugmasini bosing.
5. iOS so'raganda **Allow** qiling (Settings > Notifications'da ham ko'rinadi).
6. Supabase `device_tokens` jadvalida o'zingizning profilingizga tegishli
   `platform = web`, `is_active = true` yozuv yaratilganini tekshiring.
7. Boshqa qurilmadan yangi chat xabari, ariza holati yoki vazifa yuboring.
8. iPhone ekranini qulflang. Push kelishi va bosilganda kerakli bo'lim
   ochilishini sinab ko'ring.

Push kelmasa, avval `notification-worker` loglari va `device_tokens` jadvalini
tekshiring. iOS PWA'da ruxsat tugmasi aynan **Home Screen'ga o'rnatilgan**
ServicePro ichidan bosilishi shart. Safari ichidagi oddiy tabdan push ruxsati
olish iPhone'da ishlamasligi mumkin.

## Chegaralar

- Ilova ichidagi arizalar va chat Supabase orqali sinxronlanadi; webga
  mos kelmaydigan boshqa native funksiyalar alohida testni talab qiladi.
- iOS brauzer/WebKit bilan bog'liq kam uchraydigan push uzilishlari bo'lishi
  mumkin; haqiqiy iPhone'da fon rejimi testi o'tkazilmaguncha yetkazib
  berish 100% kafolatlanmaydi.
- Bu paketda jonli Firebase/Supabase konsollarida hech qanday amal
  bajarilmadi; SQL, worker va hosting deploy yuqoridagi tartibda qilinadi.
