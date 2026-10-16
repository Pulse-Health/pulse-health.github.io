import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

// Release signing: from the git-ignored `keystore.properties` (storeFile, storePassword, keyAlias, keyPassword) or, in CI, from the
// environment (PULSE_KEYSTORE_FILE, PULSE_KEYSTORE_PASSWORD, PULSE_KEY_ALIAS, PULSE_KEY_PASSWORD). Without either the release build
// is produced UNSIGNED (fine for checking that it builds; Google Play needs a signed bundle). See android/RELEASING.md.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("keystore.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

fun signingValue(propertyKey: String, environmentKey: String): String? =
    (keystoreProperties.getProperty(propertyKey) ?: System.getenv(environmentKey))?.takeIf { it.isNotBlank() }

val releaseStoreFile = signingValue("storeFile", "PULSE_KEYSTORE_FILE")
val releaseStorePassword = signingValue("storePassword", "PULSE_KEYSTORE_PASSWORD")
val releaseKeyAlias = signingValue("keyAlias", "PULSE_KEY_ALIAS")
val releaseKeyPassword = signingValue("keyPassword", "PULSE_KEY_PASSWORD")
val hasReleaseSigning = listOf(releaseStoreFile, releaseStorePassword, releaseKeyAlias, releaseKeyPassword).all { it != null }

if (providers.gradleProperty("pulse.requireSigning").isPresent && !hasReleaseSigning) {
    throw GradleException(
        "pulse.requireSigning is set but no release signing configuration was found. " +
            "Provide android/keystore.properties or the PULSE_KEYSTORE_* environment variables (see android/RELEASING.md).",
    )
}

// The 50 form-demo photos in src/exerciseMedia/assets are NOT cleared media (their licence is unknown, they show identifiable people and brand
// marks; see android/README.md, "Exercise photos"). They stay in debug builds and tests, and a RELEASE build only ships them with
// -Ppulse.includeExerciseMedia=true (or PULSE_INCLUDE_EXERCISE_MEDIA=true) after they were replaced by licensed ones. Without them the app
// shows its placeholder tile and no photo attribution.
val includeExerciseMedia =
    (providers.gradleProperty("pulse.includeExerciseMedia").orNull ?: System.getenv("PULSE_INCLUDE_EXERCISE_MEDIA")) == "true"

android {
    namespace = "health.pulse.strength"
    compileSdk = 37

    defaultConfig {
        // Placeholder identity, shared with the iOS app's bundle id (health.pulse.strength). Change it BEFORE the first Play upload:
        // an application id can never be changed afterwards.
        applicationId = "health.pulse.strength"
        minSdk = 26
        targetSdk = 36
        // CI passes the run number as PULSE_VERSION_CODE; Google Play needs a strictly increasing integer for every upload.
        versionCode = (providers.gradleProperty("pulse.versionCode").orNull ?: System.getenv("PULSE_VERSION_CODE"))?.trim()?.toIntOrNull() ?: 1
        // A blank value (an empty -Ppulse.versionName=) counts as not set: AGP would otherwise leave the versionName out altogether.
        versionName = providers.gradleProperty("pulse.versionName").orNull?.takeIf { it.isNotBlank() } ?: "1.0.0"
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = rootProject.file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            if (hasReleaseSigning) signingConfig = signingConfigs.getByName("release")
        }
        debug {
            // Lets a debug build live next to the Play Store install.
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
    }

    buildFeatures {
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    packaging {
        resources {
            excludes += setOf("/META-INF/{AL2.0,LGPL2.1}", "/META-INF/DEPENDENCIES", "/META-INF/LICENSE*", "/META-INF/NOTICE*")
        }
    }

    dependenciesInfo {
        // Google Play uses the dependency list of the bundle to warn about vulnerable libraries; sideloaded APKs do not need it.
        includeInApk = false
        includeInBundle = true
    }

    lint {
        abortOnError = true
        checkReleaseBuilds = true
        warningsAsErrors = false
        // targetSdk 36 is deliberate: Google Play requires 36 since 31 Aug 2026 and API 37's behaviour changes have not been tested.
        disable += "OldTargetApi"
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
        }
    }

    sourceSets {
        getByName("debug").assets.srcDir("src/exerciseMedia/assets")
        if (includeExerciseMedia) getByName("release").assets.srcDir("src/exerciseMedia/assets")
    }
}

dependencies {
    implementation(project(":core"))
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.foundation)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material.icons.extended)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.androidx.health.connect.client)

    testImplementation(platform(libs.androidx.compose.bom))
    testImplementation(libs.junit)
    testImplementation(libs.truth)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.robolectric)
    testImplementation(libs.androidx.test.core)
    testImplementation(libs.androidx.test.ext.junit)
    testImplementation(libs.androidx.compose.ui.test.junit4)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
}
