# ServicePro — Ishchilar vazifalari, kunlik hisobotlar va havolali reklamalar

## O‘rnatish tartibi

1. Mavjud bazaning zaxira nusxasini oling. Birinchi sinovni **test/staging** loyihasida bajaring.
2. Avvalgi `servicepro_schema.sql` va loyiha migratsiyalari, jumladan `servicepro_private` sxemasi o‘rnatilgan bo‘lishi kerak. Oldingi abonent billing SQL fayllari o‘z holicha qoladi.
3. Supabase Dashboard → SQL Editor orqali **`supabase/WORK_ACTIVITY_ADS_SETUP.sql`** faylini bir marta ishga tushiring. SQL yangi jadvallar, alohida xususiy media bucket, RLS siyosatlari, ish jarayoni funksiyalari va reklama URL ustunlarini qo‘shadi. **Bazaning eski ishlarini/qarzdorlik tarixini o‘chirmaydi.**
4. Flutter loyihasida `flutter pub get`, `flutter analyze`, `flutter test` ishga tushiring va Android, iOS, Windows qurilmalarida sinang. Yangi Flutter kutubxonalari qo‘shilmagan.
5. Avvalgi muhit sozlamasini (`.env`), Android imzolash fayllarini (`android/key.properties`, `android/app/upload-keystore.jks`) xavfsiz saqlab qo‘ying. Yetkaziladigan ZIPga ushbu **maxfiy fayllar** va qurilma/Gradle keshlari kiritilmagan. Release build uchun imzolash sozlamalarini shaxsiy kompyuteringizda qaytaring.

> **Muhim:** Yangi SQL live Supabase bazangizga avtomatik ishga tushirilmagan. Kod bazaga yozishi uchun SQLni avval test muhitida tekshirib, keyin siz boshqaradigan Supabase loyihasida o‘rnatish zarur.

## Rollar bo‘yicha imkoniyatlar

| Rol | Menyu | Imkoniyat |
| --- | --- | --- |
| Direktor/Admin | **Vazifalar va hisobotlar** hamda **Ishchilar** ichidagi tugma | O‘z tashkilotidagi ishchiga topshiriq, muddat, manzil, muhimlik va ixtiyoriy rasm/video berish; bajarilgan ishni ko‘rish; tasdiqlash, izoh bilan qayta ishlashga qaytarish yoki topshiriqni bekor qilish. |
| Ishchi | **Vazifalar va hisobotlar** (mobil pastki menyuda ham) | O‘ziga biriktirilgan vazifalarni ko‘rish/boshlash; bajarilgan ish uchun majburiy rasm/video va tavsif yuborish; mustaqil kunlik ish hisoboti yaratish; rad etilganini tuzatib qayta yuborish. |
| Direktor/Admin/Ishchi | Har bir ish kartasi | Foto/video dalillar va vaqt bo‘yicha o‘zgarishlar tarixini ko‘rish. |
| Reklama yaratish huquqiga ega avvalgi rollar | **Reklama** | Sarlavha, matn, media, auditoriya, ixtiyoriy URL va tugma nomini kiritish; keyinchalik tahrirlash va o‘chirish. |
| Reklama qabul qiluvchilar | Bosh sahifa / reklama oynasi / bildirishnoma | **Batafsil** yoki belgilangan tugma orqali tashqi havolani ochish. |

## Ish jarayonining qoidalari

- Rahbar topshirig‘i: `assigned` → `in_progress` → `submitted` → `approved`; yoki `submitted` → `rework` → qayta `submitted`. Rahbar `assigned/in_progress/rework` topshirig‘ini bekor qilishi mumkin.
- Mustaqil kunlik hisobot darhol `submitted` holatida yaratiladi. Rahbar tasdiqlaydi yoki sabab yozib qaytaradi; ishchi uni **yangi dalillar** bilan qayta yuboradi.
- Ishchining yuborishi va qayta yuborishida **kamida bitta rasm yoki video majburiy**. Rahbar topshiriqqa fayl biriktirishi ixtiyoriy.
- Har safar yuborilgan dalil faylining nomi va vaqt/izoh `work_item_events`da saqlanadi. Yangi dalillar avvalgi tarixni o‘chirmaydi. Ishchining akkaunti o‘chirilsa ham ishlar tarixi saqlanishi uchun bog‘lama `ON DELETE SET NULL` qilingan.
- Media `work-evidence` nomli **private** Storage bucket'da saqlanadi. Ilovada ko‘rish uchun muddati 15 daqiqa bo‘lgan vaqtinchalik imzolangan URL olinadi. 8 tagacha fayl, jami 120 MB; har bir rasm 10 MB, har bir video 80 MB.
- RLS direktor/adminni o‘z kompaniyasi bilan, ishchini faqat o‘zi bajaradigan ishlar bilan chegaralaydi. O‘zgartirish huquqi faqat nazoratli RPC funksiyalarda; mijoz jadvallarga bevosita yangi ish yozolmaydi.
- Tashkilot panelida ishlarni matn, ishchi, holat, vazifa/hisobot bo‘yicha filtrlang; ro‘yxat 100 tadan sahifalab yuklanadi.

## Reklama URL xavfsizligi

- Ixtiyoriy URL faqat to‘liq `https://` yoki `http://` manzil bo‘lishi mumkin; `javascript:`, `file:`, bo‘sh host, kirish ma’lumotli URLlar va 2048 belgidan uzun URLlar qabul qilinmaydi.
- URL va tugma nomi reklamaning **public/master** va alohida qabul qiluvchilarga yuboriladigan barcha xabarlarida saqlanadi. Tahrirlashda ham barcha guruh qatorlari yangilanadi.
- Tashqi link operatsion tizimning brauzerida ochiladi. Bosishdan oldin domenni tekshirish tavsiya qilinadi: bu ixtiyoriy reklama havolasi, ServicePro'ning rasmiy to‘lov kanali degani emas.

## Deploy oldidan sinov ssenariylari

1. A kompaniya direktori A ishchisiga `Ipak yo‘li 50, yerto‘la` uchun rasmli topshiriq yuborsin. Ishchi vazifani pastki menyudan ko‘rsin. B kompaniya admini A ishini ko‘ra olmasin.
2. Ishchi rasm/video biriktirmasdan ish yakunlamoqchi bo‘lsin — UI va server rad etsin. Biriktirgandan so‘ng rahbar `submitted` hisobotini ko‘rsin.
3. Rahbar qayta ishlashga izoh bilan qaytarsin; ishchi yangi rasm/video bilan yuborsin. Eski rasm va ikki yuborish ham `Tarix`dan ochilsin.
4. Ishchi o‘zi qilgan hudud tozalash ishi bo‘yicha kunlik hisobot yuborsin, rahbar tasdiqlasin. Tasdiqlangan holatni ishchi ko‘rsin.
5. Manzil bo‘yicha qidiruv, ishchi va status filtrlarini, keyingi 100 ta ishni yuklashni sinang.
6. Reklamani faqat matn bilan, media bilan, havola bilan va havolasiz yuboring. Dashboard, reklama kartasi, bildirishnomadan ochilishini tekshiring. URLni tahrir qilib eski qabul qiluvchilarda ham yangilanganini tekshiring.
7. `javascript:` va noto‘g‘ri link bilan reklama yuborishni sinang — bloklansin. Yangi jadval siyosatini oddiy aholi profili bilan tekshirib ko‘ring.
8. Avvalgi **Arizalar, Abonentlar, Mening hisobim, Excel importlari, chat va reklama tarixini** regressiya sinovidan o‘tkazing.

### Nazorat

Manba kod va SQL yangilangan. Bu muhitda Flutter/Dart SDK yo‘q; shu sabab **`flutter analyze`, `flutter test`, mobil build va jonli Supabase migration sinovi bajarilmagan**. Kodni production’ga chiqarmasdan oldin ushbu sinovlar va test bazasidagi SQL migratsiyasi shart.
