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

// Firma de subida a Play: android/key.properties (fuera del repo). Sin el
// archivo, debug y profile compilan igual (firma de debug); un release de
// producción falla con un mensaje claro en vez de un cast a null.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasUploadKey = keystorePropertiesFile.exists()
if (hasUploadKey) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
val buildsProductionRelease = gradle.startParameter.taskNames.any {
    it.contains("ProductionRelease", ignoreCase = true)
}
if (buildsProductionRelease && !hasUploadKey) {
    throw GradleException(
        "Falta android/key.properties: un release de producción tiene que " +
            "firmarse con la clave de subida a Play (ver docs/ops).",
    )
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
        if (hasUploadKey) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Sin clave de subida (dev/staging local): firma de debug, que
            // Play rechaza; producción ya cortó arriba.
            signingConfig =
                if (hasUploadKey) {
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Tests JVM del selector del widget (PortyFeedPickerTest). `org.json` de
    // Android es un stub en JVM: hace falta la implementación real.
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}
