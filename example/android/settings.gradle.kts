// Android Gradle Plugin does not run on JDK 25+ (Android Studio's bundled JBR).
// Gradle then fails with only the version string as the message, e.g. "25.0.2".
run {
    val version = System.getProperty("java.version").orEmpty()
    val major = version.substringBefore(".").substringBefore("-").toIntOrNull() ?: 0
    if (major >= 25) {
        throw GradleException(
            """
            Android build requires JDK 17 or 21, not JDK $major ($version).
            Flutter is using Android Studio's JBR by default.

            Fix (pick one):
              flutter config --jdk-dir="$(/usr/libexec/java_home -v 17)"
              org.gradle.java.home=<path-to-jdk-17> in example/android/gradle.properties
            """.trimIndent(),
        )
    }
}

pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.9.1" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
    id("org.jetbrains.kotlin.jvm") version "1.9.24" apply false
    id("org.jetbrains.kotlin.plugin.serialization") version "1.9.24" apply false
    id("com.vanniktech.maven.publish") version "0.35.0" apply false
}

// Local ECR SDK module — only when ecrSdkDependency=project in gradle.properties.
val ecrSdkProps = java.util.Properties()
file("gradle.properties").takeIf { it.exists() }?.inputStream()?.use { ecrSdkProps.load(it) }
if (ecrSdkProps.getProperty("ecrSdkDependency", "jar") == "project") {
    val ecrSdkRoot = ecrSdkProps.getProperty("ecrSdkRoot", "../../../ECR-simulator")
    include(":ecr-sdk")
    project(":ecr-sdk").projectDir = file("$ecrSdkRoot/ecr-sdk")
}

include(":app")
