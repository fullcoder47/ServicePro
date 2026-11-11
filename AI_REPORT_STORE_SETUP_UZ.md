# ServicePro AI: Microsoft Store 11.16 talabi

Bu patch faqat `lib/features/chat/ai_chat_page.dart` faylini o‘zgartiradi va yangi SQL migratsiyasini qo‘shadi. `Gemini` so‘rovlari, mavjud chat, ariza, billing, super admin, bildirishnoma va navigatsiya kodlari o‘zgarmagan.

## 1. Supabase SQL

Supabase Dashboard → SQL Editor'da faqat `supabase/migrations/20261018093000_ai_content_reports.sql` faylini ishga tushiring. Eski `servicepro_schema.sql` yoki boshqa migratsiyalarni qayta ishga tushirmang. SQL yangi `public.ai_content_reports` jadvalini yaratadi. Authenticated foydalanuvchi faqat shikoyat *yubora* oladi, oddiy foydalanuvchiga jadvalni o‘qish yoki moderatsiya qilish huquqi berilmagan.

## 2. AI bo‘limida sinov

1. ServicePro AI sahifasida hisobga kirib, savol yuboring.
2. Haqiqiy AI javobining pastidagi **Shikoyat / Report** tugmasini bosing.
3. Sababni tanlab, ixtiyoriy izoh bilan yuboring.
4. `Shikoyatingiz qabul qilindi` xabari paydo bo‘lishini tekshiring.
5. Supabase Dashboard → Table Editor → `ai_content_reports` jadvalida yangi qator `pending` holatida paydo bo‘lishini tekshiring.
6. Developer/moderator ushbu jadvalda `status`, `reviewer_notes`, `reviewed_at` maydonlarini boshqaradi. Nomaqbul javoblar bo‘yicha muammoni tekshirish va zarur tuzatishlarni amalga oshirish kerak. Jadvalni muntazam nazorat qilib boring.
7. Android va Windows ekranlarida tugmani sinab ko‘ring.

## 3. Build va Microsoft Store

Avval zaxira nusxada sinang:

```powershell
flutter pub get
flutter analyze
flutter run -d windows
```

Yangi Windows paket versiyasi Microsoft Store'ga yuklangan avvalgi versiyadan yuqori bo‘lishi kerak. `pubspec.yaml` va `msix_config` ni avtomatik tahrir qilmadik. Masalan, oldingi Store paketi `1.0.0.0` bo‘lsa, `msix_version: 1.0.0.1` qilib oshirish mumkin. So‘ng:

```powershell
flutter build windows --release
dart run msix:create
```

Partner Center → Packages'da eski versiyadan yuqori yangi `.msix` yuklang, submission'ni sertifikatlashga qayta yuboring. Microsoft testchilari ko‘rishi uchun Sertifikatlash eslatmalarida ServicePro AI javobi ostida **Shikoyat / Report** tugmasi borligini yozing. Faqat funksiyani qo‘shish sertifikatlashdan o‘tishni kafolatlamaydi; Microsoft talablariga mos moderatsiya amaliyoti ham zarur.

**Maxfiylik:** shikoyat bilan tanlangan AI javobi, unga tegishli savol va hisob identifikatori Supabase’da saqlanadi. Maxfiylik siyosatini shu ma’lumotlar yig‘ilishini aks ettirish uchun tekshiring.

**Eslatma:** Supabase API ishlashi uchun foydalanuvchining sessiyasi bo‘lishi kerak (AI bo‘limi avvaldan login talab qiladi). Internet bo‘lmasa shikoyat yuborish muvaffaqiyatsiz tugaydi va qayta urinish taklif etiladi.
