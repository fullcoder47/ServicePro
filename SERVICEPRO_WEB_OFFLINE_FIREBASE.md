# ServicePro — Flutter Web "Siz offline siz" xatosi tuzatildi

## Sababi

`AppState.checkInternetNow()` brauzerda `InternetAddress.lookup()` ishlatgan. Flutter Web brauzer sandboxi DNS lookup'ga ruxsat bermaydi. Natijada haqiqiy internet ulangan bo‘lsa ham ilova noto‘g‘ri offline sahifaga o‘tgan.

## Tuzatish

- Web: DNS-probe o‘rniga foydalanuvchi sahifalari ochiladi; haqiqiy Supabase so‘rovlari o‘z xatolarini ko‘rsatadi. Internet kerak bo‘lgan amallar onlayn bo‘lganda ishlaydi.
- Android / Windows / macOS native: oldingi DNS tekshiruvi shartlari saqlangan.
- `lib/core/platform/internet_probe_*.dart` — platformaga ajratilgan kod; web build endi `dart:io InternetAddress` ni chaqirmaydi.

## Windows'da sinash

ZIP'ni **yangi papkaga** oching. Eski ishlaydigan Android/Windows loyihangizni o‘chirmang.

```powershell
flutter pub get
flutter analyze
flutter run -d chrome
```

Brauzerda eski offline sahifa qolsa, ishga tushirilgan dasturini to‘xtatib, qayta `flutter run -d chrome` qiling va Chrome'da `Ctrl+Shift+R` bosing. Agar boshqa xatolik chiqsa, terminal yoki Chrome DevTools xabari kerak bo‘ladi.

## Mavjud Firebase'ning bepul Hosting'iga chiqarish

Firebase konsolida `zayaflkalar` loyihasi ServicePro Android ilovalari bilan bog‘langan. Unda Spark (bepul) tarif faol, Hosting bo‘limida hali **Get started** ko‘rinmoqda. Birinchi deploydan oldin aynan shu loyiha tanlanganini tasdiqlang.

```powershell
flutter build web --release
npm install -g firebase-tools
firebase login
firebase deploy --only hosting --project zayaflkalar
```

`firebase.json` bu loyihada allaqachon `build/web` papkasini ko‘rsatadi. `firebase login` uchun o‘zingizning Google akkauntingiz bilan kiring. Hech kimga parolingiz yoki tokenlaringizni yubormang.

Hosting birinchi marta faollashtirilgan va deploy muvaffaqiyatli yakunlangandan so‘ng taxminiy manzillar:

- Ilova: `https://zayaflkalar.web.app/`
- O‘rnatish sahifasi: `https://zayaflkalar.web.app/install.html`

Bu manzillar **deploy tugamaguncha tayyor sayt degani emas**. iPhone’da Safari → Share → Add to Home Screen; Mac’da Safari → File → Add to Dock.

## Cheklovlar

- Flutter SDK va Safari/iOS qurilma bu tahrir muhitida yo‘q; loyiha kodi moslashtirildi, lekin real qurilmada build va media sinovi kerak.
- PWA Web Push hozircha yoqilmagan. Supabase orqali ilova ichidagi xabarlar ishlaydi.
- Bu PWA — App Store'ga joylanadigan native `.ipa` emas.
