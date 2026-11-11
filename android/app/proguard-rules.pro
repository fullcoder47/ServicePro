# Flutter embedding/plugin registrant uchun safe rules.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.**

# Firebase, Google Play Services, Supabase/OkHttp kutubxonalari o‘z consumer ProGuard
# rules bilan keladi. Ularni to‘liq -keep qilish APK hajmini kattalashtiradi.
# Shuning uchun faqat warninglarni jim qilamiz, R8 unused kodlarni qisqartirsin.
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**
-dontwarn javax.annotation.**
-dontwarn org.codehaus.mojo.animal_sniffer.**
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn kotlin.Unit
