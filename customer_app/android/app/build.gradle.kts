import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Read MAPS_API_KEY and signing from local files
val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localProperties.load(FileInputStream(localPropertiesFile))
}
val mapsApiKey = localProperties.getProperty("MAPS_API_KEY", "")

// Release signing: create android/key.properties (see PLAY_STORE_CHECKLIST.md)
val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties()
if (keyPropertiesFile.exists()) {
    keyProperties.load(FileInputStream(keyPropertiesFile))
}

android {
    namespace = "com.qprintsolutions.qprint"
    compileSdk = 36
    // NDK r29 required for 16 KB page size support (Google Play requirement for Android 15+).
    // Install NDK 29 via Android Studio: SDK Manager → SDK Tools → NDK (side by side) → 29.0.14033849.
    ndkVersion = "29.0.14033849"

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.qprintsolutions.qprint"
        minSdk = flutter.minSdkVersion
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey
    }

    signingConfigs {
        if (keyPropertiesFile.exists()) {
            create("release") {
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
                storeFile = keyProperties.getProperty("storeFile")?.let { rootProject.file(it) } ?: rootProject.file("upload-keystore.jks")
                storePassword = keyProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keyPropertiesFile.exists()) signingConfigs.getByName("release") else signingConfigs.getByName("debug")  // Set key.properties for Play Store
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

// Suppress "source value 8 is obsolete" warnings from dependencies (plugins that still use Java 8)
tasks.withType<JavaCompile>().configureEach {
    options.compilerArgs.add("-Xlint:-options")
}

// Strip READ_MEDIA_IMAGES and READ_MEDIA_VIDEO from merged manifest (Play policy: use system picker only)
afterEvaluate {
    val stripMediaPermissions = {
        file(buildDir).walk().maxDepth(6).filter { it.name == "AndroidManifest.xml" }.forEach { manifest ->
            var text = manifest.readText()
            if (!text.contains("READ_MEDIA_IMAGES") && !text.contains("READ_MEDIA_VIDEO")) return@forEach
            val before = text
            text = text.replace(Regex("<uses-permission[^>]*android:name=\"android.permission.READ_MEDIA_IMAGES\"[^>]*/>\\s*"), "")
            text = text.replace(Regex("<uses-permission[^>]*android:name=\"android.permission.READ_MEDIA_VIDEO\"[^>]*/>\\s*"), "")
            if (text != before) {
                manifest.writeText(text)
                println("Stripped READ_MEDIA_IMAGES/READ_MEDIA_VIDEO from ${manifest.path}")
            }
        }
    }
    listOf("processReleaseManifest", "processDebugManifest").forEach { taskName ->
        tasks.findByName(taskName)?.doLast { stripMediaPermissions() }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
