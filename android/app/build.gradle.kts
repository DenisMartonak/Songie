import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: android/key.properties first, then the SONGIES_* environment
// variables. If neither gives a complete set, the release build falls back to the
// debug key (with a warning). Secrets are never printed.
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun signingValue(propName: String, envName: String): String? =
    (keyProps.getProperty(propName)?.takeIf { it.isNotBlank() }
        ?: System.getenv(envName)?.takeIf { it.isNotBlank() })
val releaseStoreFile: File? = run {
    val fromProps = keyProps.getProperty("storeFile")?.takeIf { it.isNotBlank() }
    if (fromProps != null) rootProject.file(fromProps)
    else System.getenv("SONGIES_KEYSTORE_PATH")?.takeIf { it.isNotBlank() }?.let { File(it) }
}
val releaseStorePassword = signingValue("storePassword", "SONGIES_KEYSTORE_PASSWORD")
val releaseKeyAlias = signingValue("keyAlias", "SONGIES_KEY_ALIAS")
val releaseKeyPassword = signingValue("keyPassword", "SONGIES_KEY_PASSWORD")
val hasReleaseKey = releaseStoreFile != null && releaseStoreFile.exists() &&
    releaseStorePassword != null && releaseKeyAlias != null && releaseKeyPassword != null

android {
    namespace = "com.songies.songies"
    compileSdk = 37 // permission_handler_android requires >= 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.songies.songies"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // youtubedl-android ships Python/yt-dlp natives for these ABIs only.
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }
    }

    packaging {
        // youtubedl-android executes its bundled binaries from the lib dir.
        jniLibs {
            useLegacyPackaging = true
        }
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = releaseStoreFile
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            // No minifyEnabled: the yt-dlp/Python natives must keep working.
            if (hasReleaseKey) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "Release build signed with the DEBUG key: it cannot update a release install"
                )
                signingConfig = signingConfigs.getByName("debug")
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

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("io.github.junkfood02.youtubedl-android:library:0.18.1")
}
