# ServicePro — Abonentlar va Excel billing

## O‘rnatish

1. **Mavjud ma’lumotlar bazasidan backup oling.** Yangi funksiyani dastlab test loyihasida tekshiring.
2. Supabase Dashboard → SQL Editor’da `supabase/SUBSCRIBER_BILLING_SETUP.sql` faylini ishga tushiring. Agar avval o‘rnatilgan bo‘lsa, qayta ishlatish shart emas.
3. **Yangi:** `supabase/BILLING_SELF_LINK_SETUP.sql` faylini SQL Editor’da ishga tushiring. U faqat yangi biriktirish so‘rovlari jadvali va ruxsatli funksiyalarini qo‘shadi; mavjud balans, import tarixi va qo‘lda biriktirilgan abonentlar o‘zgarmaydi.
4. Flutter loyihasi ildizida `flutter pub get` ishga tushiring. Yangi paketlar: `file_picker 11.0.3`, `excel_community 2.6.2` (mavjud `archive 4.x` bilan mos).
5. `flutter analyze` va `flutter test` ni ishga tushiring, so‘ng Android, iOS va Windows qurilmalarida import va barcha rollarni sinang.
6. Super Admin → **Excel importlari** → tashkilotni tanlash → `.xlsx` yuklash. Importdan oldin satrlar sonini tekshiring va tasdiqlang.

**Muhim:** Yangilangan ZIP manba kod nusxasidir. Maxfiy ma’lumot saqlovchi `.env`, `node_modules`, Android Gradle keshi va oldingi yig‘ilgan Windows distributivi arxivga kiritilmagan. Ishga tushirish uchun avvalgi loyihangizdagi `.env` sozlamasini xavfsiz ravishda saqlab qoling; `flutter pub get` yangi `pubspec.lock`ni yangilaydi.

## Foydalanuvchi bo‘limlari

- **Direktor/Admin:** Abonentlar — tashkilot doirasida qidirish, ko‘cha, uy, abonent turi, shartnoma bo‘yicha filtrlash, sahifalash, filtrlangan ro‘yxatni Excelga eksport qilish, shaxsiy kartani ochish va tasdiqlangan aholi profiliga **qo‘lda biriktirish (avvalgidek)**. Yangi **Aholining biriktirish so‘rovlari** oynasida aholi yuborgan hisob raqami/manzil so‘rovini ko‘radi, to‘g‘ri abonentni qidirib tanlaydi va tasdiqlaydi yoki rad etadi.
- **Super Admin:** Abonentlar — barcha tashkilotlar bo‘yicha qidirish; Excel importlari — fayl yuklash, avvalgi importlarni ko‘rish va asl Excelni qayta yuklab olish.
- **Aholi:** Mening hisobim — ro‘yxatdan o‘tishda yozgan yashash manzilini ko‘radi va tahrirlaydi (murojaatlar uchun ishlatiladigan avvalgi `resident_addresses` ma’lumoti yangilanadi). Hisob raqamini kiritib yoki manzili orqali tizimga qidiruv/biriktirish so‘rovini yuboradi. Tasdiqdan so‘ng o‘z balansi, oylik hisob-kitob, haqiqiy to‘lovlar va murojaatlarini ko‘radi. Qo‘lda biriktirilgan eski hisoblar ham darhol ko‘rinishda qoladi.

### Biriktirish xavfsizligi

- Faqat hisob raqamini yoki manzilni bilish **qarzdorlikni ko‘rish huquqini bermaydi**. Bu ma’lumotlar faqat mos abonentni *taxminan topish* uchun ishlatiladi; tashkilot direktori/admini yoki Super Admin tekshirganidan so‘ng bog‘lanadi.
- Aholi faqat **o‘zi ro‘yxatdan o‘tgan kompaniya** doirasida so‘rov yubora oladi. Manzil bo‘yicha qidiruv ilovada ro‘yxatdan o‘tgan manzilni oladi, foydalanuvchi uni “Mening hisobim” sahifasida o‘zgartira oladi.
- Tekshirilgan tasdiq ham kompaniya chegarasini va akkauntning boshqa aholiga allaqachon bog‘lanmaganini SQL darajasida tekshiradi. Direktorga/adminlarga boshqa kompaniya so‘rovlari berilmaydi.
- Yangi so‘rov yuborilganda avvalgi kutilayotgan so‘rov `cancelled` holatiga o‘tadi, **tarixdan o‘chirilmaydi**. Bitta aholi profili 24 soatda 10 ta so‘rovgacha yubora oladi.
- Yangi SQL o‘rnatilmasa ham eski qo‘lda bog‘langan hisoblar “Mening hisobim”da ko‘rinadi; faqat yangi so‘rov yuborish xizmati vaqtincha ishlamaydi.

## Excel formati

Asosiy varaqda kamida `Hisob raqami` va `Balans` bo‘lishi zarur. Boshqa taniqli ustunlar: `№`, `Viloyat`, `Tuman`, `Kompaniya`, `Uy manzili`, `Shartnoma holati`, `Abonent`, `Turi`, `Kadastr raqami`.

Ixtiyoriy varaqlar:

| Varaq | Kerakli ustunlar | Qo‘shimcha ustunlar |
| --- | --- | --- |
| Oylik hisob-kitob | `Hisob raqami`, `Yil`, `Oy` | `Umumiy maydon`, `Tarif`, `Oy boshida`, `Hisoblangan`, `Penya`, `To‘lov`, `Qayta hisob kitob`, `Oy oxirida` |
| To‘lovlar | `Hisob raqami`, `To‘lov summasi`, `To‘lov sanasi` | `Tranzaksiya`, `To‘lov turi` |
| Qayta hisob | `Hisob raqami`, `To‘lov summasi`, `To‘lov sanasi` | `Tranzaksiya` |

Izoh: Yuborilgan `export (34).xlsx` faylida **1 398 ta abonent** va **8 ta ustun** bor. Unda ism-familiya, abonent turi, kadastr, oylik hisoblanma va real tranzaksiya yozuvlari yo‘q. Ilovada bu ma’lumotlar bo‘shligicha ko‘rinadi; balansdagi ikki import orasidagi farq avtomatik tarzda «to‘lov» hisoblanmaydi.

## Import xavfsizligi va tarix

- Yuklashga faqat Super Admin ruxsatli (bazada ham RLS/RPC orqali tekshiriladi).
- Asl `.xlsx` `billing-imports` nomli **xususiy** Storage bucket’da saqlanadi.
- Har yuklash `billing_imports` va `billing_import_rows`da tarixiy nusxa yaratadi; eskilari o‘chirilmaydi.
- Import satrlari 200 tadan bosqichma-bosqich yuboriladi. Faqat barcha satrlar tekshirilgach, bitta `billing_publish_import` tranzaksiyasida joriy balanslar yangilanadi.
- Yuklash chala qolsa, oldingi joriy balanslar saqlanib qoladi; muvaffaqiyatsiz yoki tugallanmagan import holati tarixda ko‘rinadi.
- Yangi Excelda yo‘q hisoblar arxivda qoladi, ammo joriy abonentlar ro‘yxatida faol ko‘rinmaydi. Shuning uchun **har bir import tashkilotning to‘liq ro‘yxati** bo‘lishi kerak.
- Aholi raqam yoki manzil kiritib **biriktirish so‘rovi** yuboradi. Bog‘lashni direktor, admin yoki Super Admin tasdiqlaydi; foydalanuvchi hisobni o‘zi egallay olmaydi.

## Tekshirish uchun tavsiya etilgan ssenariylar

1. 1 398 satrli Excelni test kompaniyasiga import qiling; birinchi va oxirgi hisob raqamlarini tekshiring.
2. Bitta balansni o‘zgartirgan ikkinchi Excelni import qiling; yangi balans chiqishini, ikkala eski/yangi snapshot arxivda qolishini tekshiring.
3. Noto‘g‘ri balans yoki takrorlangan hisob raqami bilan importni sinang; eski joriy balans o‘zgarmasin.
4. Bir tashkilot direktori boshqa tashkilot abonentlarini ko‘ra olmasligini tekshiring.
5. Aholi foydalanuvchisi biriktirilmaganda qarzdorlik ko‘rinmasligini, admin biriktirgandan keyin faqat o‘z abonenti ko‘rinishini tekshiring.
6. Asl Excelni arxivdan yuklab olib, manba bilan solishtiring.
7. Aholi profilida manzilni “Ipak yo‘li / 50, 1” tarzida saqlang; “Manzil orqali tekshirish” so‘rovini yuboring va direktor paneli → Abonentlar → Biriktirish so‘rovlari oynasida paydo bo‘lishini tekshiring.
8. Xuddi shu profil bilan hisob raqami orqali so‘rov yuboring; direktor tasdiqlamaguncha qarzdorlik ochilmasin, tasdiqlangach faqat o‘sha hisob ochilsin.
9. Boshqa kompaniya hisobiga biriktirish, allaqachon boshqaga biriktirilgan hisobni qayta egallash va begona so‘rovlarni o‘qish bloklanishini tekshiring.

**Eslatma:** Ushbu muhitda Flutter/Dart SDK mavjud bo‘lmagani uchun mobil build va Supabase’ga jonli SQL tekshiruvi bu yerda bajarilmadi. Ular deploy oldidan yuqoridagi tartibda bajarilishi shart.
