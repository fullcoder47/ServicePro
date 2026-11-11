# ServicePro — Play yangilash (1.0.5+18)

## Shu nusxada tuzatilganlar

1. **Pastki navigatsiya:** og‘ir `IndexedStack` o‘rniga faqat ochilgan sahifani chizadigan `PageView.builder`; mavjud sahifalarning scroll/form holati saqlanadi. Nav foni GPU’ga og‘ir tushgan `BackdropFilter` o‘rniga yengil, yarim shaffof fon bilan ishlaydi. Aktiv tugmaning yumshoq animatsiyasi saqlandi.
2. **Haqiqiy ishchi reytingi:** faqat bajarilgan ariza bo‘yicha aholi kiritgan `worker_ratings` yozuvlari asosida o‘rtacha baho va baholar soni ko‘rsatiladi. Super admin yon menyusida **Reytinglar** bo‘limi bor, barcha tashkilotlarning ishchilari va ularning baho/izohlari ko‘rinadi. Baho kiritilmagan ishchiga sun’iy yulduz berilmaydi.
3. **Super admin → Foydalanuvchilar:** tashkilot tanlash, qidiruv, rol belgilash, lavozim yozish va saqlash. Uzun ro‘yxat faqat ko‘rinadigan elementlarni chizadi (`ListView.builder`). Super admin hisobini oddiy admin qilib o‘zgartirish cheklangan.
4. Reytingni yangilash so‘rovi ikki marta yuborilishidan himoya va internet xatosida avval olingan haqiqiy baholarni saqlab qolish qo‘shildi.
5. Flutter versiya raqami `1.0.5+18` ga oshirildi. **Play Console’dagi eng katta versionCode 18 yoki undan katta bo‘lsa, uni keyingi bo‘sh raqamga oshiring.**

## Real reyting uchun Supabase talabi

Loyihadagi mavjud `supabase/migrations/20261009122140_guest_staff_access.sql` va `supabase/migrations/20261013115038_workforce_notifications.sql` migratsiyalari ma’lumotlar bazasida avvaldan qo‘llangan bo‘lishi kerak. `servicepro_rate_work` va `servicepro_team_directory` RPC funksiyalari hamda `worker_ratings` jadvali shular orqali ishlaydi. Ushbu ZIP **Supabase’ga avtomatik o‘zgarish kiritmaydi**. Production ma’lumotlar bazasida SQL ishga tushirishdan avval staging’da sinang va backup oling; allaqachon ishlayotgan migratsiyani ko‘r-ko‘rona takrorlamang.

## Ishga tushirishdan oldingi tekshiruv

Windows PowerShell’da loyiha papkasidan:

```powershell
flutter pub get
flutter analyze
flutter run -d windows
flutter run -d <android-device-id>
```

Tekshiring:

- Pastki panelda 5–10 marta tez-tez sahifani almashtiring; qaytganda ro‘yxat joyi saqlangan bo‘lsin.
- Aholi hisobidan yakunlangan arizaga 1–5 yulduz bering; super admin **Reytinglar** bo‘limida o‘rtacha baho va izoh chiqishini tekshiring.
- Super admin **Foydalanuvchilar** bo‘limidan tashkilot va xodimni tanlab, rol/lavozimni o‘zgartiring; boshqa hisobda yangilangan rolni tekshiring.
- Xodim, direktor, admin va super admin hisoblarida chat, ariza, vazifa/hisobotlarni tekshiring.
- Android qurilmada chiqish uchun `flutter build appbundle --release` buyrug‘ini bajaring. Natija: `build/app/outputs/bundle/release/app-release.aab`.

**Muhim:** Ushbu muhitda Flutter SDK mavjud bo‘lmagani sababli `flutter analyze` va real qurilmadagi testlar bu yerda bajarilmadi. Play Market’ga yuklashdan oldin yuqoridagi sinovlar majburiy.
