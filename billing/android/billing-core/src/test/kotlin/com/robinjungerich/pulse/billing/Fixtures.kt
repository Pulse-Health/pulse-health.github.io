package com.robinjungerich.pulse.billing

import java.io.File

/** The shared example responses of billing/contract/fixtures, located through the `billing.contract.fixtures` system property. */
object Fixtures {
    val directory: File by lazy {
        val path = System.getProperty("billing.contract.fixtures")
            ?: throw AssertionError("System property billing.contract.fixtures is not set; run the tests through Gradle.")
        File(path).also {
            if (!it.isDirectory) {
                throw AssertionError("The contract fixtures directory is missing: ${it.path}. It lives in this repository at billing/contract/fixtures.")
            }
        }
    }

    fun names(): List<String> = directory.listFiles { file -> file.extension == "json" }!!.map { it.name }.sorted()

    fun text(name: String): String = File(directory, name).readText()
}
