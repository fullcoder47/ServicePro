# ServicePro — iPhone, iPad va macOS uchun o‘rnatiladigan veb-ilova

## Muhim farq

**Apple Developer akkauntisiz App Store’dagi `.ipa` ilovasini hamma uchun tarqatib bo‘lmaydi.**
Bu loyihada **PWA** yo‘li tanlangan: foydalanuvchi HTTPS saytdan ServicePro’ni ochadi va Safari orqali bosh ekraniga yoki Dock’ga qo‘shadi. Ikonka va mustaqil oyna paydo bo‘ladi. Android va Windows ilovalari o‘zgarmaydi.

## 1. Flutter veb-versiyasini yaratish (Windows PowerShell)

1. ZIP’ni alohida yangi papkaga oching, eski ishchi loyihangiz ustiga birdaniga yozmang.
2. Flutter SDK’ni tekshiring: `flutter doctor -v`.
3. Loyiha ichida ishga tushiring:

```powershell
flutter pub get
flutter analyze
flutter build web --release
```

Build fayllari `build/web/` ichida hosil bo‘ladi. Ularda `index.html`, `install.html`, `manifest.json`, `servicepro-sw.js` va ServicePro ikonkasi bo‘lishi kerak.

Mahalliy tarmoqdan tekshirish uchun:

```powershell
flutter run -d chrome
```

`flutter run -d chrome` tekshiruv uchun, foydalanuvchiga o‘rnatib berish uchun esa **HTTPS hosting** kerak. Real iPhone’dan tekshirishda sayt HTTPS manzilga joylashtirilgan bo‘lishi shart.

## 2. Saytga chiqarish: Firebase Hosting misoli

Loyihada `firebase.json` namunaviy hosting sozlamasi tayyor: u `build/web` ni ko‘rsatadi va Flutter sahifalariga qaytish qoidalarini beradi. Firebase Hosting’ni ishlatish uchun Firebase loyihasi va billing/hosting ruxsatlarini o‘zingiz tekshiring; Firebase Authentication/Supabase sozlamalarini almashtirmang.

```powershell
npm install -g firebase-tools
firebase login
firebase use --add
firebase deploy --only hosting
```

`firebase use --add` bosqichida mavjud Firebase loyihangizni tanlang. Uni yangi loyihaga yoki noto‘g‘ri tashkilotga ulab yubormang. Sayt manzili boshqa hostingga ham joylanishi mumkin, faqat `build/web` fayllari birgalikda xizmat qilishi va HTTPS yoqilgan bo‘lishi kerak.

Tashrif buyuruvchilarga shuni yuboring:

`https://SIZNING-DOMENINGIZ/install.html`

**Hozircha bu namuna manzil; domen tanlanmaguncha haqiqiy yuklab olish linki yo‘q.**

## 3. iPhone va iPad’da o‘rnatish

1. HTTPS saytning `/install.html` sahifasini **Safari** orqali oching.
2. **ServicePro’ni ochish** tugmasini bosing.
3. Safari’ning **Share (Ulashish)** tugmasini oching.
4. **Add to Home Screen (Bosh ekranga qo‘shish)** ni tanlang.
5. Agar **Open as Web App** kaliti ko‘rinsa, uni yoqing va **Add** ni bosing.
6. ServicePro ikonkasini bosib ilovani alohida oynada oching.

Apple brauzerida saytdagi tugma avtomatik `.ipa` yuklab bera olmaydi. Safari’da bosh ekranga qo‘shish — foydalanuvchi qiladigan qadam.

## 4. Mac’da o‘rnatish

**Veb-ilova:** macOS Sonoma 14 yoki yangirog‘ida Safari’dan saytni oching, **File → Add to Dock** ni tanlang. ServicePro Dock va Applications orqali ochiladi. Apple Developer obunasi kerak emas.

**Native Flutter macOS `.app` (ixtiyoriy):** loyiha ichidagi `macos/` scaffold saqlangan; internet va tanlangan fayllarga ruxsat (`entitlements`) qo‘shilgan. Uni yig‘ish uchun **haqiqiy Mac, Xcode va Flutter SDK** kerak:

```bash
flutter doctor -v
flutter pub get
flutter build macos --release
```

Mac’da o‘zingiz ishlatadigan local build va internetda hammaga tarqatiladigan imzolangan/notarizatsiyalangan `.app` — boshqa-boshqa jarayonlar. Ommaviy native macOS tarqatish uchun Apple’ning Developer ID imzolashi va notarizatsiyasi talab qilinishi mumkin. PWA shu murakkablikni chetlab o‘tadi.

## 5. Veb-versiya uchun qilingan moslashuvlar

- ServicePro ranglari (`#07111F`, `#D6A84F`) va haqiqiy logotip PWA ikonkalariga moslashtirildi.
- Telefon/Windows fayl yo‘li bo‘lmagan brauzer uchun rasm/video yuklash `Uint8List` orqali amalga oshiriladi; Supabase Storage’ga o‘sha mavjud bucketlar bilan yuboriladi.
- Brauzerga mos bo‘lmagan native bildirishnoma/Firebase token ro‘yxatdan o‘tkazish ishlatilmaydi. **Web push hozircha yo‘q**; ilova ichidagi Supabase bildirishnomalari saqlanadi.
- Excel eksport natijasi Windows/macOS native’da fayl orqali, veb-versiyada baytlar orqali ulashish/yuklab olishga beriladi.
- Browser uchun alohida service worker **maxfiy foydalanuvchi ma’lumotlarini keshga saqlamaydi**. Demak, hozircha offline rejim yo‘q.

## 6. Ishga tushirishdan oldingi haqiqiy tekshiruvlar

| Qurilma | Sinov |
| --- | --- |
| Chrome / Edge | Kirish, tashkilot tanlash, barcha asosiy sahifalarga o‘tish |
| iPhone Safari | `/install.html`, Add to Home Screen, ikonka va mustaqil oyna |
| iPhone Safari | Ariza + rasm yuborish, video tanlash, Supabase’da saqlanishini tekshirish |
| iPhone Safari | Saqlangan videoni ochish/o‘ynatish, chat va bildirishnomalar ro‘yxati |
| Mac Safari | Add to Dock, tashkilot vazifalari/hisobotlari, Excel eksport |
| Android / Windows | Ilgari ishlagan imkoniyatlar regressiyasiz qolganini tekshirish |

**Diqqat:** PWA brauzer cheklovlari sabab ayrim native funksiyalar aynan bir xil bo‘lmasligi mumkin. Katta videolar iOS Safari xotirasiga sig‘masligi, brauzerda telefon push’i ishlamasligi mumkin. Serverdagi RLS siyosatlari va Storage ruxsatlarini ham tekshiring; ularni ommaviy `public`ga ochmang.

## 7. Keyingi qadam

Saytni real manzilga qo‘yish uchun menga **o‘zingizga tegishli domen** yoki **qaysi hostingni tanlaganingizni** ayting. Shundan keyin birgalikda ishga tushiramiz. Hozircha kod va hosting konfiguratsiyasi tayyor, lekin internetdagi sayt alohida deploy qilinmagan.
