# ServicePro — Windows Firebase build xatosini tuzatish

## Xato nimadan chiqdi?

Siz yuborgan logda **ikki muhim belgi** bor:

- `cmake -E tar: error: ZIP decompression failed (-5)` — Firebase C++ SDK ZIP arxivi to‘liq yoki to‘g‘ri ochilmagan.
- `firebase_app.lib ... fatal error LNK1143` — Windows linker SDK kutubxonasini o‘qiy olmagan. Buning ehtimoliy sababi — shikastlangan/yarim ochilgan SDK yoki build keshi. To‘liq tekshiruv Windows kompyuteringizda bajariladi.

`59 packages have newer versions`, `CMake Deprecation Warning` va `LNK4099` (debug `.pdb`) xabarlari bu logdagi asosiy **fatal** sabab emas. Flutter/Dart paketlarini birdan yangilash shart emas.

## Eng xavfsiz ishga tushirish tartibi

1. Android Studio, ishlayotgan `flutter run` oynalari va loyiha bilan ochilgan terminalni yoping.
2. Loyihangiz `C:\Users\saman\OneDrive\Desktop\ServicePro` ichida ekan. OneDrive build natijalarini sinxronlab, fayllarni band qilishi mumkin. **Muhim tavsiya:** avval loyihani **nusxa qilib** `C:\dev\ServicePro` joyiga ko‘chiring va nusxani Android Studio'da oching. Asl OneDrive loyihasini o‘chirmang.
3. Yangi loyihada `repair_windows_firebase.ps1` fayli mavjudligini tekshiring. Loyiha ildizida **Windows PowerShell** oynasini oching.
4. Quyidagini ishga tushiring:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\repair_windows_firebase.ps1
   ```

   Bu `ExecutionPolicy` sozlamasini kompyuter bo‘yicha doimiy o‘zgartirmaydi; faqat ishga tushirilgan jarayon uchun amal qiladi. Skript kodini ishga tushirishdan oldin ko‘zdan kechiring.

5. Skript sizdagi `firebase_core` versiyasini `pubspec.lock`dan oladi, Firebase C++ SDK’ning mos versiyasini rasmiy Google manzilidan yuklaydi, arxivni **oxirigacha ochib tekshiradi**, SDK’ni OneDrive tashqarisidagi `%LOCALAPPDATA%\ServicePro\firebase-cpp-sdk`da saqlaydi va `FIREBASE_CPP_SDK_DIR` orqali FlutterFire’ga uzatadi.
6. Keyin `flutter clean`, `flutter pub get` va `flutter run -d windows` bajariladi. Faqat avtomatik generatsiya qilingan build keshi tozalanadi. `lib/`, `.env`, abonentlar, Excel ma’lumotlari, Supabase ma’lumotlar bazasi va boshqa manbalar o‘zgarmaydi.

### Faqat Windows build qilish (dastur ishga tushmasin)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\repair_windows_firebase.ps1 -BuildOnly
```

### Agar bundan keyin ham xato qolsa

`flutter doctor -v` natijasini, skript chiqishidagi **birinchi** qizil xatoni va Windows Visual Studio versiyasini yuboring. Alohida kompyuterning antivirus, proxy, disk yoki C++ toolchain holatini bu muhitdan tasdiqlab bo‘lmaydi. Hech qanday loyiha faylini qo‘lda o‘chirmang.

**Oldingi kod xatosi ham to‘g‘rilangan:** `work_media_picker.dart` ichidagi `FilePicker.platform.pickFiles()` chaqiruvi o‘rnatilgan `file_picker 11.0.3` versiyasiga mos `FilePicker.pickFiles()`ga almashtirilgan.
