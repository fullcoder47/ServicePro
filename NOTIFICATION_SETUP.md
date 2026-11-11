# ServicePro notification sozlash

Bu versiyada app ichida (foreground) local notification chiqishi, chat/ticket badge va Supabase realtime/auto-refresh qo‘shilgan.

Telefon app yopiq/background holatda ham push kelishi uchun quyidagilar shart:

1. Firebase project oching.
2. Android app package name: `com.example.servicepro` yoki o‘zingiznikini qo‘ying.
3. `google-services.json` faylini `android/app/google-services.json` joyiga qo‘ying.
4. Supabase SQL Editor’da `supabase/servicepro_schema.sql` ni qayta run qiling.
5. FCM tokenlar `device_tokens` tablega tushayotganini tekshiring.
6. FCM pushni server tomondan yuborish uchun Supabase Edge Function kerak bo‘ladi. Flutter app ichiga Firebase server kalitini qo‘yish mumkin emas.

App ichida xabar kelganda notification chiqadi. App yopiq holatda push yuborish Edge Function ulanmaguncha ishlamaydi.
