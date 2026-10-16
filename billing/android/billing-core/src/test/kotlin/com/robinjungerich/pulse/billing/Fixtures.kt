package com.robinjungerich.pulse.billing

import org.junit.Assert.fail
import java.io.File

/** The shared example responses of billing/contract/fixtures, located through the `billing.contract.fixtures` system property. */
object Fixtures {
    val directory: File by lazy {
        val path = System.getProperty("billing.contract.fixtures")
            ?: fail("System property billing.contract.fixtures is not set; run the tests through Gradle.").let { error("unreachable") }
        File(path).also {
            if (!it.isDirectory) {
                fail("The contract fixtures directory is missing: ${it.path}. It lives in this repository at billing/contract/fixtures.")
            }
        }
    }

    fun names(): List<String> = directory.listFiles { file -> file.extension == "json" }!!.map { it.name }.sorted()

    fun text(name: String): String = File(directory, name).readText()
}
