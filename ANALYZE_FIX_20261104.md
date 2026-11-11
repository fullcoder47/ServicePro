# ServicePro — `flutter analyze` xatolari uchun tuzatish

Manba: 2026-11-04 kuni yuborilgan `flutter analyze` natijasi (31 ta issue).

## Tuzatilgan kompilyatsiya xatolari

- `notification_service.dart`: `flutter_local_notifications 22.3.3`
  `initialize(settings: ...)` va `show(id:, title:, body:, notificationDetails:, payload:)` chaqiruvlariga moslashtirildi.
- `billing_imports_page.dart`: `file_picker 13.3.2` uchun bitta Excel fayli
  `pickFile()` orqali tanlanadi, ma'lumot `readAsBytes()` orqali olinadi.
- `work_media_picker.dart`: `pickFiles()` to‘g‘ridan-to‘g‘ri ro‘yxat qaytarishi,
  `PlatformFile.lengthSync()/length()` hajmni aniqlashi va
  `readAsBytes()` faylni o‘qishi hisobga olindi. Local video yo‘li mavjud
  bo‘lsa, avvalgidek video to‘liq xotiraga yuklanmaydi.

`pubspec.yaml`, `pubspec.lock`, qolgan barcha `lib` fayllar, Supabase SQL
va mavjud ma'lumotlar o‘zgartirilmadi.

## Keyingi tekshiruv

Windows'dagi ServicePro papkangizga PATCH ichidagi yangi fayllarni birlashtiring.

```powershell
flutter pub get
flutter analyze
```

Ushbu muhitda Flutter SDK yo‘qligi sabab real kompilyatsiya bajarilmadi.
Logdagi `info` (deprecated/format) va ba'zi `warning` yozuvlar kompilyatsiya
xatosidan farq qiladi; ular uchun alohida, xavfsiz bosqich kerak bo‘lishi mumkin.

**Eslatma:** Android, Windows, Web va iOS ilova yangilanishlarini paket fix
tekshirilmaguncha nashrga yubormang.
