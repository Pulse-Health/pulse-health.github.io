// CustomTabs.kt
// Terms, privacy policy and the Stripe portal open in a Custom Tab, so the user stays "in" the app.

package com.robinjungerich.pulse.billing.android.ui

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent

/** Opens [url] in a Custom Tab, or in the default browser when there is no Custom Tabs provider. Only http(s) is opened. */
fun openInCustomTab(context: Context, url: String) {
    val uri = Uri.parse(url)
    if (uri.scheme != "https" && uri.scheme != "http") return
    val tab = CustomTabsIntent.Builder().build()
    // Outside an Activity (an application context) the tab needs a task of its own.
    if (context.findActivity() == null) tab.intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    try {
        tab.launchUrl(context, uri)
    } catch (_: ActivityNotFoundException) {
        // No browser installed: nothing to open.
    }
}

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}
