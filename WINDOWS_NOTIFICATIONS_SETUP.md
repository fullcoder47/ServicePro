# ServicePro — Windows 10/11 bildirishnomalari

## Nima o'zgardi?

- Supabase `notifications` jadvalidan kelgan yangi xabarlar Windows tizim bildirishnomasi (toast) sifatida chiqadi.
- Realtime ulanish uzilganda mavjud 15 soniyalik zaxira tekshiruv yangi xabarlarni ham aniqlaydi.
- Oynaning `X` tugmasi endi ServicePro'ni to'liq o'chirmaydi; dastur soat yonidagi **system tray**ga o'tib, fon rejimida ishlashda davom etadi.
- Tray ikonkasiga bosing: oynani ochadi. O'ng tugma: oynani ochish yoki **Dasturdan to'liq chiqish**.
- Windows Store uchun MSIX `startup_task` sozlangan: foydalanuvchi Windows tizimiga kirganda dastur fon rejimida ishga tushishi mumkin. Windows **Startup Apps**da ServicePro o'chirilmagan bo'lishi kerak.
- Bildirishnoma bosilsa, oyna ochiladi va mavjud notification router tegishli sahifaga yo'naltiradi.

## Laptopda ishga tushirish

1. Windows 10/11 da loyiha papkasini oching.
2. Terminalda `flutter pub get` va `flutter analyze` ishlating.
3. `flutter run -d windows` bilan lokal sinov o'tkazing.
4. Windows **Settings > System > Notifications**da xabarnomalar yoqilganligini tekshiring. Focus assist / Do not disturb ishlayotgan bo'lsa, popup ko'rinmasligi mumkin.
5. ServicePro'da akkauntingizga kiring. Ikkinchi qurilmadan shu akkauntga yangi chat, ariza, topshiriq yoki reklama bildirishnomasi yuboring.
6. Ilova ochiq paytda toast chiqqanini, so'ng `X` bosib trayga o'tganda yana yangi xabar uchun toast chiqqanini tekshiring.
7. Tray ikonkasining o'ng tugmasida **Dasturdan to'liq chiqish** tanlovi ishlashini tekshiring.
8. Windows'ni qayta ochib, Startup Apps ruxsati yoqilgan holda fon rejimidan xabar kelishini sinang.

## Microsoft Store uchun

- `pubspec.yaml` ichidagi `msix_config` sozlamalarida mavjud `identity_name` va `publisher` ni **o'zgartirmang**.
- Yangi MSIX versiyani Microsoft Store'ga yuborishdan oldin `version` va `msix_version` qiymatlarini avvalgi Store versiyasidan yuqoriga ko'taring.
- Release jarayonida `flutter build windows --release` va `dart run msix:create --build-windows false` bajaring.
- Toast faollashtirish GUID: `10e407c0-c655-465d-a470-9201087f70b8` (MSIX va Dart kodida bir xil bo'lishi kerak).

## Muhim texnik cheklov

Ushbu yechim oynani **yopgandan keyin** ishlaydi, chunki ServicePro trayda fon jarayoni sifatida faol qoladi. Dastur Task Manager orqali majburan tugatilsa, traydagi **to'liq chiqish** tanlansa yoki kompyuter o'chirilsa, uning Supabase ulanishi ham uziladi. Jarayon butunlay o'chiq bo'lgan paytda ham yangi xabarni yetkazish uchun alohida Windows Push Notification Service (WNS) va server-side jo'natish integratsiyasi kerak. FCM'ning Flutter Windows versiyasi mavjud Android/iOS qurilma tokeni kabi ishlamaydi.

Windows build va haqiqiy laptopdagi sinov bosqichlari ushbu manba kod topshirilgach bajarilishi shart.
