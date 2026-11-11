# ServicePro scheduled notifications setup

Bu update Super Admin panelida “Rejali bildirishnomalar” sahifasini qo‘shadi. Super Admin:

- barcha 7 kunni tanlaydi yoki ayrim hafta kunlarini belgilaydi;
- aniq sanani tanlaydi;
- Toshkent vaqti bo‘yicha notification vaqtini tanlaydi;
- sarlavha va matn yozadi;
- rejalangan notificationni yoqadi/o‘chiradi;
- xohlagan payt “Hozir yuborish” qiladi.

## 1) SQL

Supabase SQL Editor’da `supabase/servicepro_schema.sql` ni qayta run qiling.

## 2) Edge Functions deploy

Oldingi `send-push` function yangilandi. Yangi worker ham qo‘shildi.

```bash
supabase functions deploy send-push
supabase functions deploy scheduled-push-runner
```

Secrets oldin qanday bo‘lsa shunday qoladi:

- `SUPABASE_SERVICE_ROLE_KEY`
- `FIREBASE_PROJECT_ID`
- `FIREBASE_CLIENT_EMAIL`
- `FIREBASE_PRIVATE_KEY`

## 3) Scheduler

Productionda notification app yopiq bo‘lsa ham vaqtida ketishi uchun `scheduled-push-runner` function avtomatik chaqirilishi kerak.

Supabase Dashboard → Edge Functions → scheduled-push-runner → Schedule/cron bo‘limidan har 1 daqiqada ishga tushadigan schedule qo‘ying.

Cron:

```text
* * * * *
```

Worker Toshkent vaqtini UTC+5 qilib hisoblaydi va `scheduled_notifications` jadvalidagi tanlangan kun/sana va vaqt kelgan bo‘lsa, hamma foydalanuvchilarga push yuboradi.

## 4) Test

1. Super Admin bilan kiring.
2. Menyu → Rejali bildirishnomalar.
3. Yangi reja yarating.
4. Vaqtni hozirgi Toshkent vaqtiga yaqinroq qilib belgilang.
5. Scheduler ishga tushganini Edge Function logs’dan tekshiring.
