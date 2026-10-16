package health.pulse.strength.ui.settings

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.core.net.toUri
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import health.pulse.strength.StrengthAppEnvironment
import health.pulse.strength.health.HealthConnectSupport
import health.pulse.strength.ui.PrivacyLinks
import health.pulse.strength.ui.theme.PulseFont
import health.pulse.strength.ui.theme.PulseMetrics
import health.pulse.strength.ui.theme.PulseTheme
import health.pulse.strength.ui.theme.pulseCard
import health.pulse.strength.ui.theme.pulseClickable
import health.pulse.strength.ui.theme.pulseMinHeight
import kotlinx.coroutines.launch

/**
 * Settings and About: notifications, Health Connect, the privacy policy, contact, version and attributions. The hub opens it from a
 * settings icon in its top bar.
 */
@Composable
fun SettingsScreen(environment: StrengthAppEnvironment, onBack: () -> Unit, modifier: Modifier = Modifier) {
    val colors = PulseTheme.colors
    val context = LocalContext.current
    val services = environment.services
    val scope = rememberCoroutineScope()

    var notificationsOn by remember { mutableStateOf(areNotificationsOn(context)) }
    val notificationLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        notificationsOn = areNotificationsOn(context)
        if (granted) services?.onNotificationPermissionResult()
    }

    val healthConnectEnabled by (services?.settings?.healthConnectEnabled
        ?: remember { kotlinx.coroutines.flow.MutableStateFlow(false) }).collectAsState()
    var availability by remember { mutableStateOf(HealthConnectSupport.availability(context)) }
    var healthMessage by remember { mutableStateOf<String?>(null) }

    // The screen sends the user to system screens (notification settings, Health Connect, the store): look at the real state again
    // when they come back, instead of showing what it was when the screen opened.
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        val wasOn = notificationsOn
        notificationsOn = areNotificationsOn(context)
        // Notifications were just turned on for a workout that is already running: show its notification now.
        if (notificationsOn && !wasOn) services?.onNotificationPermissionResult()
        availability = HealthConnectSupport.availability(context)
        val settings = services?.settings
        if (settings != null && settings.healthConnectEnabled.value) {
            scope.launch {
                // A switch that is on although Health Connect cannot take the workouts would silently save nothing: say so, turn it off.
                val problem = HealthConnectSupport.problem(availability, HealthConnectSupport.permissionState(context))
                if (problem != null) {
                    settings.setHealthConnectEnabled(false)
                    healthMessage = problem
                }
            }
        }
    }
    val healthLauncher = rememberLauncherForActivityResult(PermissionController.createRequestPermissionResultContract()) { granted ->
        val allowed = granted.containsAll(HealthConnectSupport.permissions)
        services?.settings?.setHealthConnectEnabled(allowed)
        healthMessage = if (allowed) null else "Permission was not granted, so workouts are not saved to Health Connect."
    }

    Box(modifier.fillMaxSize().background(colors.ground).safeDrawingPadding(), contentAlignment = Alignment.TopCenter) {
        Column(
            Modifier
                .widthIn(max = PulseMetrics.maxContentWidth)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = PulseMetrics.screenInset, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Row(Modifier.fillMaxWidth().pulseMinHeight(56.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier
                        .pulseMinHeight(48.dp)
                        .widthIn(min = 48.dp)
                        .semantics { contentDescription = "Back" }
                        .pulseClickable(role = Role.Button, onClick = onBack),
                    contentAlignment = Alignment.Center,
                ) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, contentDescription = null, tint = colors.ink) }
                Text("Settings", style = PulseFont.title, color = colors.ink, modifier = Modifier.padding(start = 4.dp))
            }

            Section("Notifications") {
                Text(
                    if (notificationsOn) {
                        "On. The running workout shows in your notifications with buttons to log a set and control the rest timer, " +
                            "and a sound plays when a rest is over while the app is in the background."
                    } else {
                        "Off. Turn notifications on to log sets and control the rest timer from the lock screen, " +
                            "and to hear when a rest is over while the app is in the background."
                    },
                    style = PulseFont.subhead,
                    color = colors.inkSecondary,
                )
                ActionRow(
                    title = if (notificationsOn) "Notification settings" else "Allow notifications",
                    onClick = {
                        if (!notificationsOn && Build.VERSION.SDK_INT >= 33 && services?.settings?.notificationPermissionAsked != true) {
                            services?.settings?.notificationPermissionAsked = true
                            notificationLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                        } else {
                            openNotificationSettings(context)
                        }
                    },
                )
            }

            Section("Health Connect") {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text("Save workouts to Health Connect", style = PulseFont.headline, color = colors.ink)
                        Text(
                            "Each finished workout is saved as a strength-training session. The app only writes; it never reads your health data.",
                            style = PulseFont.footnote,
                            color = colors.inkSecondary,
                        )
                    }
                    Switch(
                        checked = healthConnectEnabled,
                        onCheckedChange = { wantsOn ->
                            healthMessage = null
                            availability = HealthConnectSupport.availability(context)
                            if (!wantsOn) {
                                services?.settings?.setHealthConnectEnabled(false)
                            } else {
                                when (availability) {
                                    HealthConnectSupport.Availability.AVAILABLE -> scope.launch {
                                        if (HealthConnectSupport.hasWritePermission(context)) {
                                            services?.settings?.setHealthConnectEnabled(true)
                                        } else {
                                            healthLauncher.launch(HealthConnectSupport.permissions)
                                        }
                                    }
                                    HealthConnectSupport.Availability.UPDATE_REQUIRED ->
                                        healthMessage = "Health Connect needs an update before it can be used."
                                    HealthConnectSupport.Availability.UNAVAILABLE ->
                                        healthMessage = "Health Connect is not available on this device."
                                }
                            }
                        },
                        colors = SwitchDefaults.colors(checkedTrackColor = colors.green, checkedThumbColor = colors.onGreen),
                    )
                }
                healthMessage?.let { Text(it, style = PulseFont.footnote, color = colors.destructive) }
                if (availability == HealthConnectSupport.Availability.AVAILABLE) {
                    ActionRow(title = "Manage in Health Connect", onClick = { openHealthConnect(context) })
                } else if (availability == HealthConnectSupport.Availability.UPDATE_REQUIRED) {
                    ActionRow(title = "Update Health Connect", onClick = { openHealthConnectStore(context) })
                }
            }

            Section("Privacy") {
                Text(
                    "Pulse Strength works entirely on your device. It has no accounts and no internet access: your workouts, templates and " +
                        "exercises are stored in the app and in your Android backup if you use one. Nothing is sent to us or to anyone else.",
                    style = PulseFont.subhead,
                    color = colors.inkSecondary,
                )
                ActionRow(title = "Privacy policy", onClick = { openUrl(context, PrivacyLinks.policyUrl) })
            }

            Section("About") {
                InfoRow("Version", versionName(context))
                InfoRow("Exercise photos", "Free Exercise DB (public domain)")
                ActionRow(title = "Contact", onClick = { sendEmail(context) })
                Text(
                    "Built with Kotlin, Jetpack Compose and other open-source software under the Apache License 2.0.",
                    style = PulseFont.footnote,
                    color = colors.inkTertiary,
                )
            }
        }
    }
}

@Composable
private fun Section(title: String, content: @Composable () -> Unit) {
    val colors = PulseTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            title.uppercase(),
            style = PulseFont.text(13.sp, FontWeight.SemiBold),
            color = colors.inkSecondary,
            modifier = Modifier.padding(horizontal = 4.dp).semantics { heading() },
        )
        Column(
            Modifier.fillMaxWidth().pulseCard().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) { content() }
    }
}

@Composable
private fun ActionRow(title: String, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().pulseMinHeight(48.dp).pulseClickable(role = Role.Button, onClick = onClick),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, style = PulseFont.text(17.sp, FontWeight.SemiBold), color = PulseTheme.colors.greenText)
    }
}

@Composable
private fun InfoRow(label: String, value: String) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, style = PulseFont.body, color = PulseTheme.colors.ink)
        Text(value, style = PulseFont.body, color = PulseTheme.colors.inkSecondary)
    }
}

private fun areNotificationsOn(context: Context): Boolean = health.pulse.strength.services.WorkoutNotifications.canNotify(context)

private fun versionName(context: Context): String = runCatching {
    context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: ""
}.getOrDefault("")

private fun openNotificationSettings(context: Context) {
    val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
    safeStart(context, intent)
}

private fun openHealthConnect(context: Context) = safeStart(context, HealthConnectClient.getHealthConnectManageDataIntent(context))

private fun openHealthConnectStore(context: Context) {
    safeStart(context, Intent(Intent.ACTION_VIEW, "market://details?id=com.google.android.apps.healthdata".toUri()))
}

private fun openUrl(context: Context, url: String) = safeStart(context, Intent(Intent.ACTION_VIEW, url.toUri()))

private fun sendEmail(context: Context) {
    safeStart(context, Intent(Intent.ACTION_SENDTO, "mailto:${PrivacyLinks.supportEmail}".toUri()))
}

private fun safeStart(context: Context, intent: Intent) {
    try {
        context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    } catch (_: ActivityNotFoundException) {
        // Nothing can handle it on this device; the row simply does nothing.
    }
}

@Suppress("unused")
private fun hasPermission(context: Context, permission: String): Boolean =
    ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
