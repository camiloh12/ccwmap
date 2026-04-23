import java.util.Properties
import java.io.FileInputStream
import java.io.File

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load keystore properties from local file for dev builds. CI overrides
// these at runtime via environment variables (see release.yml / production.yml).
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}
val isCi = System.getenv("CI") == "true"

android {
    namespace = "com.ccwmap.ccwmap"
    compileSdk = 36  // Required by dependencies (androidx.browser, androidx.core)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    defaultConfig {
        applicationId = "com.ccwmap.app"
        minSdk = flutter.minSdkVersion  // Minimum Android 5.0 (Lollipop)
        targetSdk = 35  // Required for 2026 Play Store compliance
        // Read from pubspec.yaml via the Flutter Gradle plugin so CI's
        // stamp step (sed on pubspec) actually takes effect. Previously
        // hardcoded to 0.2.0 / 4, which caused Play Internal to display
        // 0.2.0 regardless of what pubspec said.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (isCi) {
                val keystorePath = System.getenv("ANDROID_KEYSTORE_PATH") ?: "app/release.jks"
                storeFile = rootProject.file(keystorePath)
                storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("ANDROID_KEY_ALIAS")
                keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
            } else {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = keystoreProperties.getProperty("storeFile")?.let { File(it) }
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-DEBUG"
            // Debug builds use debug signing automatically
        }

        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_21
    }
}

flutter {
    source = "../.."
}
