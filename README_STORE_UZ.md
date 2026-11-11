# ServicePro — Microsoft Store uchun qayta nashr

## Avvalgi rad etilishlar
1. 11.16: ServicePro AI — Report/shikoyat. Joriy ZIPda `ai_chat_page.dart` va SQL migratsiyasi mavjud. Supabase orqali haqiqiy shikoyat yuborilganini tekshiring.
2. 10.1.1.11: On Device Tiles — standart ikonka. Yangi MSIX ichidagi tile resurslari ServicePro oltin logotipi ekanini tekshiring.

## Ushbu PATCHda o'zgargan narsa
- `pubspec.yaml`: faqat Microsoft Store versiyasi `1.0.3.0` qilindi, `logo_path` nisbiy yo'lga almashtirildi, `trim_logo: false` qo'shildi. Android versiyasi va barcha MS Store identity qiymatlari o'zgarmadi.
- `Check-ServiceProMsix.ps1`: yangi MSIX faylining nusxasini ochib `AppxManifest.xml` identifikatorlari va rasmlarni ko'rsatadi; haqiqiy MSIXga tegmaydi.
- `ServicePro_Store_300x300.png`: Store listing'ning 1:1 App tile icon maydoni uchun ixtiyoriy rasm. Asl logo o'zgarmagan.

## Xavfsiz o'rnatish
1. Avval asl loyihangizni zaxiralang.
2. PATCH ichidagi `pubspec.yaml` ni ServicePro root papkasiga qo'ying. `Check-ServiceProMsix.ps1` ni ham root papkaga qo'ying. PNG faylini MS Store Store listings > Store logos qismida ishlatishingiz mumkin.
3. Windows PowerShell (ServicePro root):

```powershell
flutter pub get
flutter analyze
flutter build windows --release
dart run msix:create --build-windows false
powershell -ExecutionPolicy Bypass -File .\Check-ServiceProMsix.ps1
```

Agar CMake ZIP decompress xatosi bo'lsa: `flutter clean`, `flutter pub get` va qayta build qiling. OneDrive bilan muammo qaytalansa, loyihaning NUSXASINI `C:\FlutterProjects\ServicePro` ga ko'chiring. `logo_path` nisbiy bo'lgani sababli bu ishlaydi.

4. MSIX tekshiruv papkasidagi ikonlarni oching: barcha ko'rinadigan Start/Tile logolar ServicePro logosi bo'lishi kerak; Flutter/Microsoft placeholderlari bo'lmasin.
5. Windows App Certification Kit (Windows SDK) bilan tayyor .msix-ni tekshiring.
6. Store ro'yxati tavsifiga AI haqidagi ma'lumotni qo'shing; shikoyat funksiyasi Windows release'da haqiqiy ishlayotganini tekshiring.
7. Partner Center > ServicePro > Draft submission > Packages: oldingi paketni yangi 1.0.3.0 paket bilan almashtirib, sertifikatsiyaga yuboring.

Microsoft oxirgi qabul qilgan yoki rad etgan paket versiyasi 1.0.3.0 yoki undan yuqori bo'lsa, `msix_version` ni undan ham balandroq (oxirgi raqam 0) qilib qo'ying.

## Tekshiruv uchun izoh (Notes for certification)
We addressed Microsoft Store Policy 10.1.1.11 by packaging ServicePro-specific Windows tile and Start menu icons. We have also provided a "Report" action below AI-generated responses in the ServicePro AI page, allowing users to report inappropriate content for developer review (Policy 11.16). Please verify both features in this updated package.

> Diqqat: loyiha muhitida Windows SDK/Flutter kompilyatori mavjud emas. MSIX bu yerda build qilinmagan va avtomatik Microsoft sertifikatsiyasi kafolatlanmaydi. Tekshiruv skripti natijalarini va mahalliy Windows App Certification Kit natijasini ko'rib keyin yuboring.
