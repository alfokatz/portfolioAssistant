import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// FCM: google-services.json sale de la consola de Firebase (no está en el
// repo). Sin el archivo la app compila igual y funciona sin push.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.portfolioassistant.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications lo exige.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // Id de Porty en Google Play. NO se puede cambiar después de la
        // primera subida. `namespace` (paquete del código Kotlin) queda como
        // estaba: es independiente del applicationId.
        applicationId = "com.portyassistant.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Un flavor por entorno: cada uno es una app distinta (se pueden instalar
    // juntas) y tiene su propia app en Firebase. `--flavor X` también elige
    // assets/env/.env.X (ver _setupEnviroment en lib/main.dart).
    //   flutter run --flavor development
    //   flutter build appbundle --flavor production   ← Play Store
    //   flutter build apk --flavor staging            ← Firebase App Distribution
    buildFeatures {
        resValues = true // app_name por flavor (AGP 9 lo trae apagado)
    }

    flavorDimensions += "env"
    productFlavors {
        create("development") {
            dimension = "env"
            applicationIdSuffix = ".dev"
            resValue("string", "app_name", "Porty Dev")
        }
        create("staging") {
            dimension = "env"
            applicationIdSuffix = ".staging"
            resValue("string", "app_name", "Porty Staging")
        }
        create("production") {
            dimension = "env"
            resValue("string", "app_name", "Porty")
        }
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Tests JVM del selector del widget (PortyFeedPickerTest). `org.json` de
    // Android es un stub en JVM: hace falta la implementación real.
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}
