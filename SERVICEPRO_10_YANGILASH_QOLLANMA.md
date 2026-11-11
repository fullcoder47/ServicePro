# ServicePro 10 — arizalar, Excel va super admin

## 1. Muhim: avval ma’lumotlar bazasi yangilanishi kerak

1. **Supabase Dashboard → SQL Editor → New query** oching.
2. `supabase/migrations/20261031180000_work_excel_admin_ticket_cycles.sql` faylidagi SQL ni kiriting va ishga tushiring.
3. Bu **qo‘shimcha migratsiya**. U eski arizalarni, raqamlarni, vazifalarni yoki media fayllarni o‘chirmaydi. Xatolik bo‘lsa, `BEGIN`/`COMMIT` sababli tranzaksiya ortga qaytadi.
4. **Ishlab turgan bazada** yangilashdan oldin Supabase zaxira nusxasi yoki staging bazada sinov qiling. `servicepro_schema.sql` va `WORK_ACTIVITY_ADS_SETUP.sql` fayllarini qayta to‘liq ishga tushirish shart emas.

## 2. Yangi imkoniyatlar

- **Arizalar → yuklab olish:** `.xlsx` fayl; **Arizalar** varag‘i ma’lumotlar, **Rasmlar** varag‘i biriktirilgan fotolarni Excel faylining ichida saqlaydi. Videolar fayl manbasi sifatida ko‘rsatiladi.
- **Vazifalar va hisobotlar → yuklab olish:** `.xlsx` fayl; **Vazifalar**, **Hisobotlar**, **Arxiv**, **Rasmlar** varaqlari. Super admin barcha tashkilotlarni, direktor/admin esa o‘z tashkilotini eksport qiladi.
- **Super admin → Tashkilotlar → kerakli tashkilot → Raqamlashni qayta boshlash:** eski arizalar saqlanadi. Yangi davrdagi birinchi raqam misol uchun `SP-2026-R000001-000001`; keyingisi `...-000002`. Har davrga yangi global `R` belgisi beriladi, shu bois arizalar raqami takrorlanmaydi.
- **Super admin → Vazifalar va hisobotlar:** tashkilot bo‘yicha saralash, yangi vazifa/hisobot yaratish, tahrirlash, tasdiqlash, arxivlash va arxivdan tiklash. Oddiy direktor va ishchiga arxivlangan yozuvlar ko‘rinmaydi.
- **Sahifalar:** og‘ir ekranlar birinchi bor ochilganda quriladi; keyin holati saqlanadi. Sahifalar orasidagi animatsiya 170 ms yumshoq o‘tadi.

## 3. Sinab ko‘rish

Windows PowerShell (ServicePro ildiz papkasida):

```powershell
flutter pub get
flutter analyze
flutter run -d windows
```

Telefonni sinash uchun:

```powershell
flutter devices
flutter run -d <device-id>
```

Tekshiruv ro‘yxati:

1. Direktor **Arizalar**dan Excel yuklasin; rasmli 1–2 arizani Excelda ochib `Rasmlar` varag‘ini tekshirsin.
2. Direktor **Vazifalar va hisobotlar**dan Excel yuklasin; vazifa, hisobot, rasm hamda mavjud videolar ro‘yxatini tekshirsin.
3. Super admin kompaniya sahifasida raqamlashni boshlasin; yangi arizani yaratsin. **Eski raqam o‘zgarmaganiga**, yangi davrda `000001` bo‘lganiga ishonch hosil qilsin.
4. Yana bir ariza yaratsin: `000002` bo‘lishi kerak. Boshqa kompaniyani qayta boshlash oldingisiga ta’sir qilmasligi lozim.
5. Super admin vazifa yaratsin, tahrirlasin, arxivlasin va tiklasin. Arxivdagi rasm va tarix saqlanganini tekshirsin.
6. Telefon va Windows’da sahifalar orasida yurib, mavjud chat, ariza yuborish va media ko‘rish oqimlarini tekshirsin.

**Eslatma:** Bu muhitda Flutter SDK mavjud emasligi sababli `flutter analyze`, haqiqiy Windows build va mobil qurilmadagi ishlashini shu yerda tekshirish imkoni bo‘lmadi. Yuqoridagi buyruqlarda xatolik chiqsa, terminalning to‘liq logini yuboring — o‘sha aniq qatorni tuzatish kerak bo‘ladi.
