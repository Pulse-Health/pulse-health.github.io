plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    api(libs.coroutines.core)
    api(libs.okhttp)
    api(libs.kotlinx.serialization.json)

    testImplementation(libs.junit)
    testImplementation(libs.coroutines.test)
    testImplementation(libs.okhttp.mockwebserver)
}

val contractFixtures = rootProject.layout.projectDirectory.dir("../contract/fixtures")

tasks.test {
    // The contract fixtures live outside this Gradle project; the contract tests fail (not skip) when they are missing.
    systemProperty("billing.contract.fixtures", contractFixtures.asFile.absolutePath)
    inputs.dir(contractFixtures).optional().withPathSensitivity(PathSensitivity.RELATIVE)
}
