# ServicePro — mehmon rejimi va tashkilotlar kirishi

**Holat: SINOV UCHUN NOMZOD.** Jonli baza o‘zgartirilmagan, Play Marketga joylanmagan. APK/AAB va qurilmadagi ko‘rinish hali tasdiqlanmagan.

## Amalga oshirilgan o‘zgarishlar

- Birinchi ochishda auth o‘rniga to‘rtta bo‘limli mehmon rejimi. Shaxsiy arizalar va tashkilot yozishmalari profilga kirgandan keyin ochiladi.
- Birinchi ariza oldidan tashkilot, ism, familiya, telefon, parol, mahalla, ko‘cha, uy raqami saqlanadi. So‘ng ariza sahifasi ochiladi, manzil to‘ldiriladi.
- BIG SCAN AS PLYUS / PLUS mavjud bo‘lsa standart tanlov; tashkilotlar serverdan olinadi. Soxta tashkilot yaratilmaydi.
- Qayta o‘rnatgandan keyin tashkilot + telefon + parol bilan kirish. Mavjud email/parol akkauntlari uchun eski kirish saqlangan.
- Profil → Tashkilot bo‘limiga o‘tish: direktor, admin, ishchi. Direktor, admin va ishchi bir xil tashkilot kirish kodini ishlatadi. BIG SCAN AS PLYUS uchun mavjud kod saqlanadi. Har bir xodim birinchi kirishda o‘z shaxsiy parolini yaratadi; ishchi lavozimini yozadi. Keyingi kirishda umumiy kod va shaxsiy parol ishlatiladi.
- Tashkilot yaratish serverda faqat superadminga ruxsat etilgan. Umumiy tashkilot kodini bilgan yangi xodim direktor, admin yoki ishchi sifatida ro‘yxatdan o‘tishi mumkin — bu so‘ralgan tartib. Mavjud akkaunt roli bu kod bilan o‘zgarmaydi; superadmin roli hech qachon berilmaydi.
- Ishchi arizani qabul qiladi va o‘ziga biriktirilgan arizani tavsif + foto/video bilan yakunlaydi. Bir arizani ikki kishi qabul qilishi serverda cheklanadi.
- Chat: qidiruv birinchi; tashkilot nomidagi guruh; ishchilar kontaktlari; shaxsiy suhbatlar. Avvalgi reply, tahrir, o‘chirish, media, pin, typing va o‘qilganlik imkoniyatlari saqlangan.
- Tab almashganda sahifalar holati IndexedStack orqali saqlanadi.
- Dashboard: ariza holatlari, bajarilish ko‘rsatkichi, animatsiyali e’lonlar, ishchilar, bandlik, bajarilgan ishlar, haqiqiy reyting. Rollarga alohida ranglar va system/light/dark theme.
- Aholi o‘z yakunlangan arizasini 1–5 baholaydi. Soxta reyting va maosh yo‘q.
- Superadmin tashkilotning umumiy kodini va ishchi rolini boshqaradi, lavozim va maoshni tahrirlaydi. Avvalgi tashkilot, foydalanuvchi, chat, e’lon va bildirishnomalar boshqaruvi saqlangan.
- Maosh alohida himoyalangan jadvalda: superadmin, o‘z tashkilotining direktor/admini va xodimning o‘zi ko‘radi. Uy manzili boshqa aholiga ochilmaydi.
- Yangi matnlar UZ/RU/EN. Eski interfeysning 100 ga yaqin statik matni va bir qancha maydonlar tarjimaga ulangan. Eski dinamik jumlalar, xato xabarlari va tizim dialoglarining barcha tarjimalari qurilmada yakuniy tekshiruvni talab qiladi. Foydalanuvchi xabarlari tarjima qilinmaydi.

## Bazani yangilash

1. Avval zaxira nusxa va alohida sinov muhitini tayyorlang.
2. Amaldagi bazada **supabase/servicepro_schema.sql ni qayta ishlatmang**: u eski auth siyosatlarini qayta tiklashi mumkin.
3. Sinov bazasida migrationlarni tartib bilan bir marta qo‘llang: avval `supabase/migrations/20261009122140_guest_staff_access.sql`, keyin `supabase/migrations/20261009133514_shared_company_staff_code.sql`. Birinchi migration avval bajarilgan bo‘lsa, uni qaytarmang — faqat ikkinchisini bajaring. Tranzaksiyali skript mavjud akkaunt, ariza va chatlarni o‘chirmaydi. Yangi baza uchun avval asosiy schema, so‘ng migration kerak.
4. Yangi kirish mavjud `@servicepro.local` identifikatorlarini davom ettiradi. Email tasdiqlash yoqilgan bo‘lsa, signup sessiya bermaydi. Amaldagi auth sozlamasini tekshiring; ishlab turgan sozlamalarni ko‘r-ko‘rona o‘zgartirmang.
5. Mavjud superadmin profili saqlanib qoladi. Faqat email matniga qarab ilovadan superadmin yaratish olib tashlangan.
6. Sinovdan so‘ng jonli bazaga qo‘llash alohida deploy bosqichi. Bu ish davomida jonli bazaga yozilmadi.

## Windows’da tekshirish

JDK/Gradle, Android package ID va imzolash sozlamalari almashtirilmagan. build, .dart_tool va node_modules keshlari ZIP’ga kiritilmagan.

```powershell
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build apk --debug
```

Yoki loyiha papkasida `./verify_update.ps1` ni bajaring. Bir bosqich xato bersa skript to‘xtaydi.

**Flutter vositasini ishga tushirish ushbu muhitning avtomatik xavfsizlik tekshiruvida bloklandi:** yuklangan vosita cloud metadata manziliga murojaat qilgan. Shuning uchun flutter analyze, widget test, APK/AAB build va real ekran renderi bu yerda bajarilgan deb hisoblanmasin. Dart sintaksisi boshqa parser bilan, baza esa alohida lokal PostgreSQL/PGlite bilan tekshirildi.

Backend testlar:

```powershell
npm install --prefix tool
npm test --prefix tool
```

Testlar lokal PGlite’da, jonli loyihaga ulanmasdan ishlaydi. Auth/JWT testda modellashtiriladi. Haqiqiy Supabase Auth, Storage, Realtime va FCM alohida sinov talab qiladi.

## Qurilmadagi sinovlar

- Toza o‘rnatish, mehmon navigatsiyasi, orqaga qaytish, internet qayta ulanishi.
- Aholi profili → ariza; qayta ochish; chiqish va qayta kirish; noto‘g‘ri parol.
- Eski aholi/direktor/admin/superadmin akkauntlari va avvalgi ma’lumotlar.
- Yangi tashkilot, umumiy tashkilot kodi, shaxsiy parol, har bir rol, noto‘g‘ri kod va boshqa tashkilot. Kodni almashtirish shaxsiy parolni o‘zgartirmaydi.
- Ikki qurilmada bir arizani qabul qilish; media bilan yakunlash; reyting.
- Chat: xabar/media, reply/edit/delete/pin, typing/read, foreground/background push.
- UZ/RU/EN, kichik ekran, katta shrift, klaviatura, dark/light/system.
- Superadmin CRUD: avval sinov yozuvlarida. Barcha eski boshqaruv amallari to‘liq regressiya sinovidan hali o‘tmagan.

Play’dan oldin oxirgi `versionCode`dan kattaroq raqam belgilang. Versiya ko‘r-ko‘rona oshirilmadi. Avval internal testing, keyin bosqichma-bosqich tarqatish.

## Amaliy chegaralar

- Telefon SMS orqali tasdiqlanmaydi; foydalanuvchi kiritgan raqam login sifatida ishlatiladi.
- Xodim identifikatori tashkilot + ism-familiyadan tuziladi. Bir tashkilotda aynan bir xil ism-familiyali ikki xodim uchun alohida noyob login mexanizmi kerak bo‘ladi.
- Mehmon barcha bo‘limlarni ko‘radi, lekin shaxsiy chat/ariza ma’lumotlari uchun profil kerak.
- “Hech qachon qayta yangilash kerak bo‘lmaydi” yoki “barcha Play testlari o‘tgan” kafolati berilmaydi. Billing integratsiyasi bu o‘zgarishga kirmaydi.

2026-10-09 tuzatish: alohida xodim kodi yaratish tugmasi olib tashlandi. Eski shaxsiy kod bilan ro‘yxatdan o‘tgan akkauntlar saqlanadi; eski kod ularning shaxsiy paroli bo‘lib qoladi. Yangi kirish ekranida tashkilotning umumiy kodi ham so‘raladi. Jonli bazaga bu tuzatish hali qo‘llanmagan.
