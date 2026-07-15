import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // Flutter Gradle Plugin must be applied after Android + Kotlin.
    id("dev.flutter.flutter-gradle-plugin")
}

// Apply the google-services plugin *only* when Firebase has been
// provisioned for this build (i.e. a google-services.json exists
// next to this file).  Keeping the plugin conditional means CI
// builds and pre-Firebase experiments still assemble cleanly.
val googleServicesJson = file("google-services.json")
if (googleServicesJson.exists()) {
    apply(plugin = "com.google.gms.google-services")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasKeystore = keystorePropertiesFile.exists()
if (hasKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.scarabgold.scarabgolden"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications 18.x pulls java.time.* APIs, which
        // need core-library desugaring on older Androids (< API 26).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.scarabgold.scarabgolden"
        // TZ: minSdk 30, targetSdk 35.
        minSdk = 30
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasKeystore) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = if (hasKeystore) {
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")

    // AppsFlyer 6.x deliberately dropped play-services-ads-identifier
    // from its transitive deps to keep the AAB slim.  Apps that want
    // GAID-based attribution (and therefore af_status: Non-organic
    // instead of always-Organic) have to pull the artifact in
    // themselves — without it AdvertisingIdClient is missing from
    // the release classpath, R8 prunes the reference, and every
    // paid OneLink install lands in the arena.
    implementation("com.google.android.gms:play-services-ads-identifier:18.2.0")
    // Not strictly required, but AppsFlyer's install-referrer path
    // uses the modern App Set ID surface when GAID is unavailable
    // (e.g. children profiles, GPS-less ROMs).  Adds ~20 KB.
    implementation("com.google.android.gms:play-services-appset:16.1.0")
}

flutter {
    source = "../.."
}
