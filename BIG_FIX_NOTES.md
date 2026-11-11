# ServicePro big fix notes

Muhim: chatda o'chirilgan xabar original matn/media bilan direktor/admin/super adminlarga ko'rinishi uchun Supabase SQL yangilandi. Supabase SQL Editor'da `supabase/servicepro_schema.sql` faylini qayta run qiling.

Qo'shilgan/tuzatilganlar:
- Auth sahifasida User default qoldi; Direktor/Admin/Login maxsus icon menyudan ochiladi.
- User telefon + kompaniya kodi bilan qayta kirsa, avvalgi profiliga qaytadi.
- Oddiy userlar uchun o'chirilgan chat xabari chatdan yo'qoladi.
- Direktor/Admin/Super Admin o'chirilgan xabarni va o'chirilgan original matn/media ma'lumotini ko'radi.
- Chat rasmlar/video fayllarini ochish/yuklab olish va faylga reply qilish qo'shildi.
- Ariza rasmlar/video fayllarini ochish/yuklab olish yaxshilandi.
- Video fayllar tashqi player orqali ochiladi.
- Super Admin sahifalariga refresh va boshqaruv yaxshilandi.
- .env maxfiy fayl zip ichiga qo'shilmadi; .env.example qoldirildi.
