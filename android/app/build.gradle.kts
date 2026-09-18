plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.ezcore.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.ezcore.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Cores + runtime dlopen by absolute path from the native library dir,
    // so ship them extracted (not page-aligned uncompressed).
    packagingOptions {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    signingConfigs {
        create("release") {
            // Release signing via environment (CI secrets or local export):
            // EZCORE_KEYSTORE_FILE, EZCORE_KEYSTORE_PASSWORD,
            // EZCORE_KEY_ALIAS, EZCORE_KEY_PASSWORD.
            val storePath = System.getenv("EZCORE_KEYSTORE_FILE")
            if (!storePath.isNullOrBlank()) {
                storeFile = file(storePath)
                storePassword = System.getenv("EZCORE_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("EZCORE_KEY_ALIAS")
                keyPassword = System.getenv("EZCORE_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // A keystore without EZCORE_KEYSTORE_FILE falls back to debug
            // keys so `flutter run --release` works; store builds must set
            // the env (scripts/release.sh fails loudly otherwise).
            val hasReleaseKeystore = System.getenv("EZCORE_KEYSTORE_FILE")
                .isNullOrBlank().not()
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
