
import java.util.Properties
import java.io.FileInputStream
val serviceProReleaseApkBuild = gradle.startParameter.taskNames.any {
    it.contains("assembleRelease", ignoreCase = true) || it.contains("packageRelease", ignoreCase = true)
}



plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")

if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.fullcoder.servicepro"
    compileSdk = flutter.compileSdkVersion
    // jni and other native dependencies require NDK 28.2 on Android.
    // Pinning the highest requested NDK avoids per-plugin version conflicts.
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "17"
    }
    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.fullcoder.servicepro"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }

    // Oddiy `flutter build apk --release` qilganda universal APK o‘rniga ABI bo‘yicha
    // alohida APKlar chiqadi. Bu app funksiyasini o‘zgartirmaydi, lekin har bir
    // telefonga tushadigan APK hajmini keskin kamaytiradi.
    // Play Market uchun esa baribir `flutter build appbundle --release` ishlatiladi.
//    splits {
//        abi {
//            isEnable = serviceProReleaseApkBuild
//            reset()
//            include("armeabi-v7a", "arm64-v8a")
//            isUniversalApk = false
//        }
//    }

    packaging {
        // APK fayl hajmini kamaytiradi: native .so fayllarni APK ichida siqilgan holda saqlaydi.
        // Android o‘rnatishda ularni o‘zi extract qiladi; app logikasi o‘zgarmaydi.
        jniLibs {
            useLegacyPackaging = true
        }
        resources {
            excludes += setOf(
                "META-INF/AL2.0",
                "META-INF/LGPL2.1",
                "META-INF/LICENSE*",
                "META-INF/NOTICE*",
                "META-INF/DEPENDENCIES"
            )
        }
    }

    buildTypes {
        release {
            // Play Marketga chiqarishdan oldin o‘z release keyingiz bilan signing qiling.
            signingConfig = signingConfigs.getByName("release")
            // APK/AAB hajmini kamaytiradi. Kod/logika o‘zgarmaydi.
            isMinifyEnabled = true
            isShrinkResources = true
            isCrunchPngs = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }


}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
