# ServicePro — Android va Windows moslashuvchan interfeysi

## Nimalar o‘zgardi

- 980px dan keng oynalarda barcha ruxsat berilgan sahifalar **chapdagi scroll qilinadigan menyu** orqali ochiladi.
- Tor oyna va Android telefonlarda **oldingi pastki navigatsiya** saqlangan.
- Mehmon (ro‘yxatdan o‘tmagan) rejimi ham ikkala kenglikka mos.
- Ish stoli uchun asosiy sahifalar markazda, maksimal kenglik bilan ko‘rsatiladi; chat/profil yanada ixcham.
- Shaxsiy/guruh chat xonasi va ServicePro AI suhbat oynasi ham katta ekranda o‘qishga qulay maksimal kenglikda ko‘rsatiladi.
- Dashboard arizalar statistika kartalari katta ekranda 4 ustunga o‘tadi.
- Ariza yaratish formasi va ariza tafsilotlari Windows’da ortiqcha cho‘zilmaydi.
- Windows dasturining ikonasi mavjud ServicePro (oltin qalqon) belgisi bilan bir xil.
- Windows’dagi video ko‘ruvchi ilova ichida ishlamasa tashqi pleer/brauzer orqali ochish imkoniyati ko‘rsatiladi; telefonlar uchun mavjud video pleer saqlanadi.
- Windows’da mobil Firebase Messaging va mobil local notification chaqiruvlari ishga tushirilmaydi. **Ilova ichidagi Supabase notification inbox saqlangan**, lekin Windows OS darajasida push yetkazish alohida integratsiya talab qiladi.
- Windows CMake 4+ uchun eski Firebase C++ SDK minimum-policy mosligi `windows/CMakeLists.txt` faylida berilgan, Flutter yoki Firebase SDK ning generatsiya qilinadigan fayllari o‘zgartirilmagan.

## Mavjud imkoniyatlar

- Android paket nomi, rol/ruxsatlar, Supabase jadval va migratsiyalari, billing, chat, arizalar mantig‘i, reklama, direktorga tegishli eksport va telefonning oldingi dizayni o‘zgartirilmagan.
- `pubspec.yaml` paket versiyalari o‘zgartirilmagan.
- Faqat yuqoridagi interfeys, Windows CMake mosligi va Windows push qo‘llab-quvvatlash nazorati tahrir qilingan.

## Windows'da tekshirish

Komandalarni ServicePro papkasida PowerShell’da bajaring:

```powershell
flutter doctor -v
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

Eslatma: **mavjud loyihada** Supabase URL va publishable key `lib/core/config/supabase_config.dart` faylida berilgan; ular o‘zgartirilmagan. Ushbu versiya `--dart-define` qiymatlarini u yerda avtomatik o‘qimaydi. `.env` fayli ham `main.dart` tomonidan avtomatik yuklanmaydi. Hozirgi ishlayotgan ulanish sozlamalarini saqlang.

Windows dasturi ochilgach uni toraytirib/kengaytirib, mehmon, aholi, admin, direktor va super admin bo‘limlarini tekshiring. So‘ng:

```powershell
flutter build windows --release
```

`build\windows\x64\runner\Release\` ichidagi `.exe` fayli bilan birga DLL va `data` fayllarini ham tarqatish zarur.

**Diqqat:** ushbu arxiv uchun bu muhitda Flutter/Dart SDK va Windows/MSVC toolchain bo‘lmagani sababli haqiqiy `flutter analyze`, widget-test va Windows release build ishlatilmadi. Yuqoridagi tekshiruvlarni o‘z Windows kompyuteringizda bajarib natijasini ko‘ring. Natijalar chiqmaguncha loyihani xatosiz deb kafolatlamang.

**Maxfiylik:** ZIP ichidagi `.env` manbadan o‘zgarmagan holda saqlangan. Uni hech qachon ochiq GitHub yoki boshqa ommaviy joyga yuklamang.
