# Super Admin Database Cleanup Fix

Bu fix Super Admin panelida quyidagilarni qo'shadi:

- Super Admin barcha tashkilot statistikalarini ko'radi.
- Har bir tashkilotning umumiy chatlarini ko'radi.
- Umumiy chatni ichidagi yozishmalari bilan databasedan butunlay o'chira oladi.
- Kompaniyani o'chirsa, unga bog'langan arizalar, reklamalar, chatlar, xabarlar, user profillari, notificationlar va device tokenlar ham tozalanadi.
- Global “Eski ma’lumotlarni tozalash” tugmasi arizalar, reklamalar, chatlar va yozishmalarni o'chiradi; kompaniya va user profillari qoladi.
- Reklama Super Admin tomonidan o'chirilsa, ad_group_id bo'yicha barcha receiver notificationlari ham databasedan o'chadi.

Muhim: Supabase SQL Editor’da `supabase/servicepro_schema.sql` faylini qayta run qiling.
Yangi RPC functionlar:

- `super_delete_chat_room`
- `super_delete_profile`
- `super_delete_company`
- `super_cleanup_activity_data`

Bu functionlar faqat `public.is_super_admin()` true bo'lsa ishlaydi.
