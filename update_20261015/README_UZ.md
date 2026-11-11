# ServicePro: navigator va tashkilot yaratish oynasi tuzatishi

Asos: sizga 2026-10-13 kuni berilgan `ServicePro_notifications_workforce.zip`, 1-versiya.
Bu tuzatish o'sha nusxa uchun tayyorlandi. Keyin kompyuteringizda shu fayllarni
tahrirlagan bo'lsangiz, almashtirishdan oldin o'z nusxangiz bilan solishtiring.

## O'zgargan uchta ilova fayli

- `lib/app.dart`: asosiy navigator kaliti State ichida bir marta yaratiladi.
  Profil/rol almashganda tegishli HomeShell holati qayta yaratiladi; theme
  o'zgarganda navigator saqlanadi. Rolga tegishli light/dark ThemeData har chat
  yoki o'qilganlik hodisasida qayta hisoblanmaydi.
- `lib/core/widgets/app_route.dart`: CurvedAnimation o'z StatefulWidget'iga
  tegishli. Rebuildda takror yaratilmaydi, parent animation almashganda eskisi
  tozalanadi va dispose'da listenerlar chiqariladi. Avvalgi fade/slide,
  easeOutCubic/easeInCubic, masofa va davomiylik saqlangan.
- `lib/features/super_admin/super_admin_page.dart`: tashkilot yaratish oynasida
  controllerlar oynaning State'iga tegishli. Pop future tugashi bilan erta
  dispose qilish olib tashlandi. Oyna faqat matn nusxalarini qaytaradi.
  Bekor qilish, orqaga tugmasi va tashqariga bosish saqlashni chaqirmaydi.
  Bo'sh qiymatlar tekshiriladi; yopilgan route'dagi tugma ikkinchi route'ni
  tasodifan yopmasligi uchun tekshiruv qo'shilgan.

Qo'shimcha test: `test/regression/navigator_dialog_lifecycle_test.dart`.

## O'rnatish

1. Ilovani Android Studio/terminalda to'liq Stop qiling.
2. Yuqoridagi uch faylning o'z kompyuteringizdagi nusxasini zaxiralang.
3. Kichik `ServicePro_navigation_fix.zip` ichidagi `lib` papkasini mavjud
   ServicePro loyiha ildiziga nusxalab, shu uch faylni almashtiring.
   To'liq loyiha ZIPidan foydalansangiz, unda ham shu tuzatishlar mavjud.
4. Test papkasini ham loyiha ildiziga qo'shing. PowerShell'da tekshiring:

```powershell
flutter analyze --no-pub
flutter test --no-pub test/regression/navigator_dialog_lifecycle_test.dart
flutter run
```

Oddiy Hot Reload bilan cheklanmang: navigator va State boshlang'ich holati uchun
to'liq Stop/Run zarur. Bu tuzatish Supabase SQL bajarishni talab qilmaydi.

## Telefonda tekshirish

- Superadmin: yangi tashkilot oynasiga matn yozing va Bekor qilishni bosing.
  Bir necha marta takrorlang; klaviatura ochiq holatda, Android orqaga tugmasi
  va tashqariga bosish orqali ham yoping.
- Yaratish: bo'sh forma saqlanmasin; to'ldirilgan forma bir marta yuborilsin.
- Profil: light/dark/system theme va tilni almashtiring, so'ng bo'limlarga o'ting.
- Hisobni almashtiring: aholi, direktor/admin, superadmin oqimlarini tekshiring.
- Tashkilot oynasini yopish paytida theme/profile yangilanishi bo'lsa ham
  bitta navigator qolishi widget testida tekshiriladi.

## Tekshiruv chegarasi

49 Dart fayli grammar tekshiruvidan o'tdi, nisbiy importlar topildi. Asosiy
ZIPdagi boshqa fayllar byte bo'yicha saqlangani paketlashda tekshirildi.

Flutter analyze, widget test, APK/AAB va telefon testi bu muhitda bajarilmadi.
Flutter/Dart SDK ijrosi avvalgi avtomatik tekshiruvda rad etilgani uchun
cheklovni aylanib o'tishga urinilmadi. Yuqoridagi beshta widget test hozircha
tayyorlangan, o'tgan deb hisoblanmaydi.

Logdagi GlobalObjectKey<NavigatorState> Flutter yaratgan navigator kalitidir.
Yuborilgan finalizeTree stack'i undan oldingi exceptionni ko'rsatmaydi.
Mazkur paket kodda aniqlangan lifecycle muammolarini tuzatadi; sizdagi aynan
shu xato bartaraf bo'lganini telefon sinovisiz tasdiqlab bo'lmaydi. Xato
takrorlansa, birinchi Exception caught satridan boshlangan to'liq log hamda
sizdagi joriy lib/app.dart va super_admin_page.dart nusxalari kerak bo'ladi.

## Rasmiy manbalar

- https://api.flutter.dev/flutter/widgets/GlobalKey-class.html
- https://api.flutter.dev/flutter/widgets/WidgetsApp/navigatorKey.html
- https://api.flutter.dev/flutter/widgets/TransitionRoute/completed.html
- https://api.flutter.dev/flutter/animation/CurvedAnimation/dispose.html
