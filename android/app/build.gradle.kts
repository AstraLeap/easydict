plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.keskai.easydict"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }


    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.keskai.easydict"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        externalNativeBuild {
            cmake {
                cppFlags += "-std=c++17"
                cFlags += "-DZSTD_STATIC_LINKING_ONLY"
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    buildTypes {
        release {
        val envKeystoreFile     = System.getenv("KEYSTORE_FILE")
            val envKeystorePassword = System.getenv("KEYSTORE_PASSWORD")
            val envKeyAlias         = System.getenv("KEY_ALIAS")
            val envKeyPassword      = System.getenv("KEY_PASSWORD")

            if (envKeystoreFile != null && envKeystorePassword != null && envKeyAlias != null && envKeyPassword != null) {
                signingConfig = signingConfigs.create("release") {
                    storeFile = file(envKeystoreFile)
                    storePassword = envKeystorePassword
                    keyAlias = envKeyAlias
                    keyPassword = envKeyPassword
                }
            } else {
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}
