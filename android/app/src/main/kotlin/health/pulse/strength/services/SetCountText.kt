package health.pulse.strength.services

/**
 * "1 set" / "3 sets". The app's texts are English only, so the plural is chosen here and the number is written with Latin digits
 * whatever the device language is (a `<plurals>` resource would pick the plural rule and the digits of the device language).
 */
internal fun setCountText(count: Int): String = if (count == 1) "1 set" else "$count sets"
