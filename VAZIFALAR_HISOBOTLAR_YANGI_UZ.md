# Vazifalar va hisobotlar — sodda variant

Ushbu yangilanish faqat `lib/features/work_activity/work_activity_page.dart`
sahifasini qayta yozadi. Mavjud `work_items`, `work_item_events`, `work-evidence`
va barcha ish/hisobot tarixi saqlanadi. Supabase bazasi, RLS va RPC funksiyalari
o'zgartirilmagan. Xodimlar, arizalar, chat va billing kodlariga tegilmagan.

## Direktorga / adminga

1. **Vazifalar** -> **Ishchiga vazifa berish**: ishchini tanlang, nom va tavsifni
   kiriting. Manzil va rasm/video ixtiyoriy.
2. **Hisobotlar**: yuborilgan natijani oching, tasdiqlang yoki sabab yozib
   qayta ishlashga yuboring.
3. Vazifa hali tugallanmagan bo'lsa, uni bekor qilish mumkin.

## Ishchiga

1. **Vazifalar**: topshiriqni boshlash, keyin rasm/video va bajarilgan ish
   tavsifini yuborish.
2. **Kunlik hisobot yuborish**: ish nomi, bajarilgan ish tafsiloti, majburiy
   foto/video va ixtiyoriy manzil.
3. Qaytarilgan hisobotga yangi foto/video qo'shib qayta yuborish.

## Muhim

- Supabase bazangizda oldingi `supabase/WORK_ACTIVITY_ADS_SETUP.sql` allaqachon
  o'rnatilgan bo'lishi kerak. Buni tekshirmasdan SQL faylni qayta ishga
  tushirmang. O'rnatilmagan bo'lsa, avval test bazasida tekshiring.
- Eski ZIPni zaxira sifatida qoldiring. Yangisini alohida papkaga ochib
  `flutter pub get`, `flutter analyze` va telefonda `flutter run -d <device>`
  bilan sinang. Ma'lumotlar bazasini tozalamang.
- Telefon uchun qo'lda tasdiqlash kerak: direktor/admin vazifa berishi,
  ishchi rasm/video bilan bajarishi, rahbar natijani tasdiqlashi, ilovadan
  chiqib qayta kirganda tarix saqlanishi.
- Bu muhitda Flutter SDK yo'q, shu sababli haqiqiy Android build yoki
  Supabase serverli sinov o'tkazilmagan. Arxiv va kodning statik tekshiruvlari
  amalga oshiriladi.

## Duplicate GlobalKey haqida

Yangi ish sahifasida `GlobalKey<FormState>` ishlatilmaydi. Bu ekranga tegishli
kalitlar muammosini chetlab o'tadi, lekin agar boshqa bo'limda yana shu xabar
chiqsa, qizil ekran xabari va uning stack trace'i kerak bo'ladi.
