# SmartCall → ServicePro (faqat hisobot)

## Ishlaydigan qism

- ServicePro'dan qo‘ng‘iroq qilinmaydi. Barcha qo‘ng‘iroqlar `smartcall.uz/web/` orqali amalga oshiriladi.
- Superadmin SmartCall guruhi nomini aniq ko‘rsatib, uni ServicePro tashkilotiga bog‘laydi.
- SmartCall webhook yuborganda, **faqat abonent “1” ni bosib operator bilan gaplashgan** yozuv kompaniyasiga bog‘langan holda Supabase'ga saqlanadi.
- Direktor va admin faqat o‘z tashkilotining hisobotlarini, superadmin barcha tashkilotlarnikini ko‘radi.
- Bitta webhook takror kelib qolsa, yozuv ikki marta saqlanmaydi.
- Maxfiy webhook token ilova kodida yoki ochiq bazada saqlanmaydi. Bir martalik token faqat superadminga chiqariladi.

## Ulash tartibi

1. Superadmin bilan ServicePro'ga kiring va yon menyudan **SmartCall hisobotlari**ni oching.
2. **Guruhni ulash**ni bosing; SmartCall'dagi guruh nomi va tegishli BSK'ni tanlang. Guruh ID ixtiyoriy. Bir xil guruh nomini ikkita tashkilotga qo‘shib bo‘lmaydi — buning uchun SmartCall'da guruh nomini farqlang.
3. **Webhook manzili**ni bosing; maxfiy URLni nusxalang. Bu manzilni begonalarga bermang.
4. SmartCall kabinetining **Webhook** bo‘limiga ushbu URLni kiriting va saqlang.
5. Tasdiqlangan test qo‘ng‘irog‘ida abonent “1” ni bosib operator bilan gaplashgach, hisobotni **Yangilash** orqali tekshiring.

## Muhim: SmartCall'dan kerakli qo‘shimcha API

SmartCall kabinetining 2026-11-04 holatidagi API hujjatida:

- Yangi qo‘ng‘iroq boshlash va uning `call_id` orqali holatini so‘rash bor;
- **SmartCall saytidan boshlangan barcha qo‘ng‘iroqlar ro‘yxatini beradigan API yo‘q**;
- Barcha audio yozuvlarni xavfsiz olish uchun umumiy `recordings` API ko‘rsatilmagan;
- **Webhook faqat yuqorida keltirilgan “1 bosgan + operator” voqeasini** beradi.

Shuning uchun **jami qo‘ng‘iroqlar, javob berilganlar, javobsizlar, barcha vaqtlar va audio** hozircha avtomatik to‘planmaydi. Ekranda bu bo‘limlar bo‘shligi aniq ko‘rsatiladi. Aks holda foydalanuvchiga noto‘g‘ri hisobot berilgan bo‘ladi.

To‘liq integratsiya uchun SmartCall texnik xizmatidan quyidagilarni so‘rash zarur:

1. SmartCall veb-interfeysida yaratilgan guruhlar bo‘yicha call history API (`groupID`, `call_id`, `phone`, `sentDate`, `answer`, `duration`, `click`, `operator`).
2. Audio yozuvni olish uchun ruxsatli va muddatli URL yoki server-to-server API.
3. Yangi qo‘ng‘iroq va holat o‘zgarishi webhooki, aks holda hisobot API'sini necha daqiqada bir so‘rash mumkinligi.

`supabase/migrations/20261104_smartcall_reports.sql` va
`supabase/functions/smartcall-webhook/index.ts` ushbu imkoniyatlar uchun
alohida, kompaniya asosida ajratilgan ma’lumot tuzilmasini yaratadi.
Android, Windows va Web hammasi bitta Supabase hisobotlarini ko‘radi.

## Maxfiylik

- API kalitini Flutter kodiga **yozmang**.
- SmartCall cookie/session kalitini ilova yoki Supabase bazasiga joylamang.
- Audio yozuvlarni tarqatishdan oldin tegishli ruxsatlar va saqlash muddatini tekshiring.
- Webhook URL oshkor bo‘lsa, `smartcall_webhook_keys` ichidagi uning `enabled` qiymatini `false`ga o‘tkazib, superadmin orqali yangi manzil yarating.
