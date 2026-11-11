# ServicePro: notification, ishchilar va arizalar yangilanishi

Asos: 2026-10-13 kuni yuborgan ServicePro(2).zip. Sizning AI, glass navbar, Excel, auth va billing kodi saqlangan. Qo'shimcha Flutter paketlari kiritilmadi. Ushbu ZIP to'liq loyiha, APK/AAB emas. O'rnatilgan Android ilovangizni o'chirish shart emas.

## Aniqlangan notification muammosi

Server tekshiruvida 33 faol qurilma, 56 ta yetkazilmagan xabar va 0 ta yuborish urinishi bor edi. notification-worker joylanmagan, eski scheduled runner ishlayotgan edi. Ilova kodi esa ochiq chatda notificationni bostirar, chat sahifasi yaratilganda hamma chatlarni o'qilgan deb belgilardi. Faqat APKni almashtirish serverdagi navbatni ishga tushirmaydi.

## Koddagi o'zgarishlar

- Qurilma tokeni chat sozlamalari so'rovidan mustaqil ro'yxatga olinadi; vaqtinchalik xatoda va ilova qayta faollashganda yana urinadi.
- Ochiq chatning ichida ham kelgan yangi xabarga ovozli notification ko'rsatiladi. Foydalanuvchi shu chatni mute qilgan bo'lsa, mute hurmat qilinadi. Senderning o'z xabariga push yuborilmaydi.
- Android uchun yangi servicepro_alerts_v2 kanali va oq small icon; release resource shrinking custom soundni olib tashlamasligi uchun keep.xml.
- Bell inbox: manba, sana/vaqt, unread belgisi, soni va kerakli ariza/chat/reklamaga o'tish. O'chirilgan ma'lumot uchun tushunarli xabar.
- Chat ro'yxatida o'qilmagan preview ajralib turadi. Alohida chatni ko'rish o'sha chatning notificationlarini o'qilgan qiladi. Faqat chat tabini ochish hammasini o'qilgan qilmaydi.
- Direktor/admin menyusida Ishchilar: kontakt, lavozim, bandligi, bajarilgan ishlar, baholar, maoshni belgilash/tahrirlash. Server faqat o'z tashkiloti ishchisi uchun ruxsat beradi.
- Ishchi menyusida Reytinglar: jami yulduzlar bo'yicha tartib, o'rtacha baho, baholar soni, o'zini belgilash. Boshqa ishchilarning maoshi ishchiga va aholiga berilmaydi.
- Qabul qilishda ishchi tanlanadi. Direktor/admin yakunlashda haqiqiy bajargan ishchini tanlaydi; completed_by ishchi, completed_by_actor amalni tasdiqlagan rahbar sifatida saqlanadi. Sana/vaqt ko'rsatiladi.
- Aholi o'zining bajarilgan arizasiga 1–5 yulduz va izoh beradi. Server ishchini arizadan oladi; qayta yuborish bahoni ko'paytirmaydi. Baho ishchi va rahbarlarga notification yaratadi.
- Bajarildi oynasida galereya, kamera orqali rasm va video; tanlashda size/count oldindan tekshiriladi. Ariza/chat videosi katta byte massiv sifatida saqlanmaydi, mahalliy fayldan yuklanadi. Yuklash vaqtida fayllar bo'yicha progress bor; bu byte tezligi o'lchovi emas.
- Aholining new/in_progress arizalari uchun 09:00 va 18:00 Asia/Tashkentda kuchli, xizmatga oid eslatma. Biriktirilgan ishchi va direktor/adminlarga boradi; ishchi hali biriktirilmagan bo'lsa shu tashkilot ishchilariga ham boradi. Completed/closed bo'lgach to'xtaydi. Eslatmada soxta jarima yoki tahdid yo'q.
- Umumiy Database tozalash kartasi olib tashlandi. Har bir tashkilot ichida o'z chatlari/arizalari/reklamalarini tozalash, bitta chatni ochish/tozalash, xabarni bosib turib tanlab o'chirish. Amal oldidan tashkilot nomi bilan tasdiq. Bazadagi yozuvlar tozalanadi; Storage'dagi ilgari yuklangan orphan fayllar bu amalda o'chirilmaydi.
- Chat xabariga bitta bosish: reaksiya, nusxa, reply, vakolatga qarab qadash/tahrirlash, ko'rganlar ro'yxati. Superadmin bosib turib bir nechta xabarni tanlay oladi.

## Backendni ishga tushirish — majburiy

Jonli serverga bu sessiyada migratsiya va deploy amalga oshirilmadi. Secret qiymatini chatga yubormang.

1. Dashboardda bazaning zaxirasini oling. Yangi migratsiyani avval test loyihasida tekshiring.
2. Supabase Edge Functions → Secrets'da NOTIFICATION_JOB_SECRET nomi bilan uzun tasodifiy sir yarating. O'sha qiymatni Vault'da notification_job_secret nomi bilan saqlang. Mavjud Firebase sirlarini o'zgartirmang: FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL, FIREBASE_PRIVATE_KEY.
3. YANGI migratsiyani ishga tushiring: supabase/migrations/20261013115038_workforce_notifications.sql. Oldingi uch migratsiya sizning serveringizda mavjud deb tekshirilgan. To'liq servicepro_schema.sqlni qayta run qilmang.
4. Loyiha terminalida CLI bilan autentifikatsiya qiling (npx supabase login), keyin:

```powershell
npx supabase functions deploy notification-worker --project-ref inbqjyypfpfqnpcjqkqn --no-verify-jwt --use-api
npx supabase functions deploy send-push --project-ref inbqjyypfpfqnpcjqkqn --no-verify-jwt --use-api
npx supabase functions deploy scheduled-push-runner --project-ref inbqjyypfpfqnpcjqkqn --no-verify-jwt --use-api
```

Bu uch funksiyaning o'z ichida autentifikatsiyasi bor: worker/runner x-job-secretni, send-push esa foydalanuvchi sessiyasini tekshiradi. Dashboarddagi legacy JWT toggle bu funksiyalar uchun OFF bo'lishi kerak. servicepro-ai ga tegmang, uning sozlamasini almashtirmang. Supabase CLI bilan ishlab ketmasa, ZIPdagi funksiyalarni Dashboarddan import qilib ham joylash mumkin.

5. update_20261013/notification_schedule.sqlni SQL Editorda run qiling. U faqat aniqlangan eski scheduled-push-runner-every-minute vazifasini pauza qiladi va yangi cronni yoqadi. INSERT trigger yangi xabarda workerni ham uyg'otadi; cron tarmoq xatolarida fallback bo'ladi.
6. Quyidagi diagnostika bilan pending/attempts o'zgarishini ko'ring. 24 soatdan eski xabarlar inboxda qoladi, eski telefon alertlari birdan yuborilmaydi. no_active_device yoki Firebase xatosi bo'lsa qayta urinish bo'ladi; 12 urinishdan keyin administrator ko'rib chiqishi kerak.

```sql
select count(*) filter(where delivered_at is null) as pending,
       count(*) filter(where attempts>0) as attempted,
       count(*) filter(where delivered_at is null and attempts>=12) as needs_review
from servicepro_private.push_jobs;
select attempts,last_error,available_at from servicepro_private.push_jobs
where delivered_at is null order by available_at limit 20;
```

## Telefon va release tekshiruvi

Flutter analyze/test/APK/AAB bu muhitda bajarilmadi. Oldingi Flutter ijrosi metadata manziliga murojaat qilgani sabab avtomatik tekshiruv tomonidan bloklangan; boshqa runtime orqali cheklov aylanib o'tilmadi. VALIDATION.md bajarilgan tekshiruvlarni ko'rsatadi.

Windows loyihasini zaxiralab, ZIPdagi ServicePro bilan yangi nusxada ishlang. Keyin:

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter build appbundle --release
```

Ikki jismoniy Android telefonda yangi va eski hisob bilan: ilova ochiq, chat ochiq, fonda va yopiq holatlarda chat/ariza/reklama/rating notificationlarini sinang. Qurilmada notification va ovoz ruxsatlari yoqilgan bo'lishi kerak. Android Settings'dan Force stop qilingan ilova uchun push ilova qayta ochilmaguncha kelmasligi mumkin; FCM ham tarmoq/OS sharoitiga bog'liq. Yetkazish qabul qilinishi va foydalanuvchi telefonida ko'rsatish bir xil tasdiq emas.

Ishchini qabul/bajarish dialoglarida tekshiring, aholi izoh bersin, reyting shu ishchiga borishini kuzating. Tozalashni haqiqiy ma'lumotlarda sinamang: test tashkilotida bajaring.

iOS uchun Info.plist ruxsatlari qo'shildi, lekin yuklangan loyihada GoogleService-Info.plist va Push entitlement yo'q edi. iOS pushni ishga tushirishdan oldin Firebase/APNs va Xcode Push capability alohida sozlanishi kerak. Android oqimi ushbu paketning asosiy release maqsadidir.

Version/build number avtomatik oshirilmadi: Play Console'dagi eng katta versionCode'dan yuqori raqam tanlang. Mavjud signing key bilan Internal testing'da tekshirib, keyin productionga chiqaring.
