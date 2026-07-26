import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.nodevisual.nodevisual_app_builder"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.nodevisual.nodevisual_app_builder"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // versionCode/versionName 直接硬编码，避免 flutter.versionCode 在
        // AGP 8.5.2 Kotlin DSL 中的函数调用兼容性问题。
        // 与 pubspec.yaml 版本对齐：0.4.14+1
        versionCode = 14
        versionName = "0.4.14"
        // Flutter Release 模式不生成 x86 的 libflutter.so / libapp.so，
        // 但部分插件会带 x86 的 .so。若 APK 包含 x86 ABI 却缺少核心库，
        // x86 模拟器 / 设备启动时会因找不到 libflutter.so 直接闪退。
        // 因此显式过滤为 Flutter 支持的 ABI。
        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a", "x86_64")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

// Kotlin JVM target 与 Java 17 对齐。
// 在 AGP 8.5.2 + Kotlin 1.9.10 中，android {} 内的 kotlinOptions 块不可用，
// 改用 tasks.withType<KotlinCompile> 配置。
tasks.withType<KotlinCompile>().configureEach {
    kotlinOptions {
        jvmTarget = "17"
    }
}

flutter {
    source = "../.."
}
