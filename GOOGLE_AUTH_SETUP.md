# ServicePro Google Auth setup

Bu update Auth sahifasiga Google orqali kirish tugmasini qo'shadi.

## Supabase Dashboard sozlamasi

1. Supabase Dashboard → Authentication → Providers → Google ni yoqing.
2. Google Cloud OAuth Client ID/Secret ni kiriting.
3. Supabase Authentication → URL Configuration → Redirect URLs ichiga qo'shing:

```text
com.fullcoder.servicepro://login-callback
```

## Google Cloud Console

Android package name:

```text
com.fullcoder.servicepro
```

Agar kerak bo'lsa SHA-1/SHA-256 ni Play App Signing va upload key bo'yicha qo'shing.

## Muhim

Google login Super Admin emaili yoki oldindan profil ochilgan email uchun ishlaydi.
Agar Google akkaunt uchun `profiles` jadvalida profil bo'lmasa, app chiroyli xabar chiqaradi va loginni bekor qiladi.
