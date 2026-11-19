plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Signing values may come from the environment or from a Gradle property of
// the same name (for example in ~/.gradle/gradle.properties). Never print
// them: they are secrets.
fun signingValue(name: String): String? =
    System.getenv(name) ?: (project.findProperty(name) as String?)

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
        // arm64-v8a only: the emulator cores ship for arm64 alone, so the
        // APK must not advertise armeabi-v7a/x86_64 support (stray
        // libdartjni copies would otherwise claim it, and an armv7 device
        // would install an app whose flutter lib isn't there). Cores are
        // arm64-only by design; the Android dev loop targets arm64
        // emulators (Apple Silicon) or devices.
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    // Cores + runtime dlopen by absolute path from the native library dir,
    // so ship them extracted (not page-aligned uncompressed).
    packagingOptions {
        jniLibs {
            useLegacyPackaging = true
            // arm64-v8a only: the emulator cores ship for arm64 alone. AAR
            // dependencies drag in stray non-arm64 copies (libdartjni.so)
            // that make the APK advertise armeabi-v7a/x86_64 device
            // support it cannot deliver — an armv7 device would install an
            // app whose Flutter libs aren't there. abiFilters is not
            // reliably applied to dependency jniLibs, so exclude by path.
            excludes += listOf(
                "lib/armeabi-v7a/**",
                "lib/x86_64/**",
                "**/armeabi-v7a/**",
                "**/x86_64/**",
            )
        }
    }

    signingConfigs {
        create("release") {
            // Release signing via environment (CI secrets or local export)
            // or a Gradle property of the same name:
            // EZCORE_KEYSTORE_FILE, EZCORE_KEYSTORE_PASSWORD,
            // EZCORE_KEY_ALIAS, EZCORE_KEY_PASSWORD.
            val storePath = signingValue("EZCORE_KEYSTORE_FILE")
            if (!storePath.isNullOrBlank()) {
                storeFile = file(storePath)
                storePassword = signingValue("EZCORE_KEYSTORE_PASSWORD")
                keyAlias = signingValue("EZCORE_KEY_ALIAS")
                keyPassword = signingValue("EZCORE_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // Without a keystore (env or Gradle property) the release build
            // uses the debug keys so `flutter run --release` works; store
            // builds must supply the four signing values.
            val hasReleaseKeystore = signingValue("EZCORE_KEYSTORE_FILE")
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
