# Backendni joylash — administrator uchun

Bu hujjat amallar ro'yxati; paket hech narsani avtomatik serverga yubormaydi. Ishlayotgan loyiha: `inbqjyypfpfqnpcjqkqn`. Avval sinov loyihasida bajaring va bazaning zaxirasini oling.

## Old shartlar

Oldingi `20261009122140_guest_staff_access.sql` va `20261009133514_shared_company_staff_code.sql` o'zgarishlari, chat jadvallari va `chat_can_access_room` mavjud bo'lishi kerak. Yangi migratsiya faqat qo'shimcha yangilanishdir. To'liq `servicepro_schema.sql`ni ishlab turgan bazada qayta ishlatmang.

Yangi migratsiya:
`supabase/migrations/20261010045723_ticket_chat_notification_reliability.sql`

Migratsiyalar tarixini `supabase migration list` bilan tekshiring. `supabase db push --dry-run` kutilmagan eski migratsiyalarni ko'rsatsa, to'xtang va tarixni moslashtiring. Faqat kerakli migratsiya qolganida `supabase db push` orqali joylang. Ishlab turgan bazada tajriba uchun reset ishlatmang.

## Edge funksiyalar va sirlar

Mavjud `FIREBASE_PROJECT_ID`, `FIREBASE_CLIENT_EMAIL`, `FIREBASE_PRIVATE_KEY` saqlanadi. Yangi uzun tasodifiy `NOTIFICATION_JOB_SECRET`ni Edge Function secrets bo'limiga kiriting. Xuddi shu qiymatni Vaultda `notification_job_secret` nomi bilan saqlang. Uni Flutter kodiga yoki gitga yozmang.

Joylanadigan funksiyalar:

```text
supabase functions deploy notification-worker --project-ref inbqjyypfpfqnpcjqkqn
supabase functions deploy send-push --project-ref inbqjyypfpfqnpcjqkqn
supabase functions deploy scheduled-push-runner --project-ref inbqjyypfpfqnpcjqkqn
```

Yangi worker va scheduled runner `x-job-secret`ni ichkarida tekshiradi. `send-push` esa foydalanuvchi tokenini tekshirib, server navbatini ishlatadigan moslik javobini qaytaradi. AI funksiyalari va ularning sirlarini almashtirmang.

## Tartibli o'tish

1. Sinov muhitida migratsiya, uch funksiya, quyidagi cron va ikkita hisob bilan yetkazishni tekshiring.
2. Ishlab turgan loyihada eski scheduled push cronlarini aniqlang. Ularning nomlarini taxmin qilib o'chirmang. O'tish vaqtida faqat tegishli eski vazifalarni pauza qiling.
3. Yangi workerni joylang, lekin cronni hali yoqmang. Migratsiyani qo'llang va darhol eski `send-push`/`scheduled-push-runner` funksiyalarini paketdagi moslik versiyalariga almashtiring. Bu amallarni bir o'tish oynasida bajaring: eski to'g'ridan-to'g'ri push va yangi navbat parallel ishlasa, takroriy bildirishnoma bo'lishi mumkin.
4. Vault va yangi cronni yoqing. Test ariza/chat/reklama orqali navbat bajarilishini tekshiring. Eski jadval ikki marta yurmasin.
5. Shundan keyin yangi Flutter versiyasini chiqaring. Eski klientlarning yangi arizalari eski manzil mantiqida qolishi mumkin; profil nusxasi yangi klient RPCsi orqali yaratiladi.

`pg_cron`, `pg_net` va Vault loyiha dashboardida yoqilgan bo'lishi kerak. Vault sirini oldindan yarating, so'ng `cron_setup.sql`ni bir marta bajaring. U bir daqiqada navbatni ishlatadi: push darhol yetib borishi kafolatlanmaydi. UI ichidagi Realtime yangilanishlari alohida ishlaydi.

## Monitoring va qayta urinish

```sql
select count(*) filter (where delivered_at is null) as pending,
       count(*) filter (where delivered_at is null and attempts >= 12) as needs_review
from servicepro_private.push_jobs;

select notification_id, attempts, available_at, last_error
from servicepro_private.push_jobs
where delivered_at is null
order by available_at;
```

12 urinishdan keyin avtomatik qayta urinish to'xtaydi. Firebase konfiguratsiyasi yoki tarmoq sababini tuzatib, administrator faqat ko'rib chiqilgan qatorlarni qayta navbatga qo'yishi mumkin. `delivered_tokens`ni tozalamang — ular muvaffaqiyatli yuborilgan qurilmalarni takror yuborishdan saqlaydi.

FCM muvaffaqiyatli javobi telefon bildirishnomani ko'rsatganini tasdiqlamaydi. Qurilma ruxsatlari, iOS APNs sozlamasi va Android kanalini haqiqiy telefonda tekshiring. Yetkazish muvaffaqiyatidan keyin server uzilib qolsa, kamdan-kam takroriy push ehtimoli qoladi; bu paket mutlaq exactly-once yetkazishni da'vo qilmaydi.

Rollback: avval cronni pauza qiling. Eski APK bilan yangi backend mosligini tekshiring; jadvallar yoki navbat ma'lumotlarini shoshilib o'chirmang. Mahalliy kodni installer yaratgan zaxiradan tiklash mumkin.
