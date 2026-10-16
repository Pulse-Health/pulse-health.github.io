// Pulse Strength for Android: widgets, tiles, Live Updates and controls around a small strength-workout core.
// Modules: :core (pure Kotlin, JVM tests), :app (phone), :wear (Wear OS). See README.md.
//
// Optional, for networks where Maven Central is not reachable: put
//   pulse.mavenCentralMirror=https://maven-central.storage-download.googleapis.com/maven2/
// in ~/.gradle/gradle.properties (never in this repository). CI uses Maven Central itself.

pluginManagement {
    val mirror = providers.gradleProperty("pulse.mavenCentralMirror").orNull
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        if (mirror != null) maven(url = mirror) else mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    val mirror = providers.gradleProperty("pulse.mavenCentralMirror").orNull
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        if (mirror != null) maven(url = mirror) else mavenCentral()
    }
}

rootProject.name = "PulseStrength"
include(":core", ":app", ":wear")
