package health.pulse.strength.widgets.home

import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.state.getAppWidgetState
import androidx.glance.appwidget.state.updateAppWidgetState
import androidx.glance.state.PreferencesGlanceStateDefinition
import androidx.lifecycle.lifecycleScope
import health.pulse.strength.R
import health.pulse.strength.core.widgets.LiftTrend
import health.pulse.strength.runtime.StrengthRuntime
import health.pulse.strength.ui.theme.PulseTheme
import kotlinx.coroutines.launch

/**
 * The configuration screen of the lift trend widget (HS-09): the user picks the lift from the snapshot's `lifts`. The launcher opens it
 * when the widget is added and again from the widget's "reconfigure" action. The choice is stored per widget id in the widget's
 * Glance preferences state ([LiftTrendWidget.LiftKey]). Backing out leaves the widget unplaced, as the platform expects.
 */
class LiftTrendConfigActivity : ComponentActivity() {
    private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        appWidgetId = intent?.extras?.getInt(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
            ?: AppWidgetManager.INVALID_APPWIDGET_ID
        setResult(RESULT_CANCELED, resultIntent())
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }
        val lifts = StrengthRuntime.snapshots.current().lifts
        setContent {
            var selectedId by remember { mutableStateOf<String?>(null) }
            LaunchedEffect(Unit) { selectedId = storedChoice() }
            PulseTheme {
                LiftPicker(lifts = lifts, selectedId = selectedId, onPick = ::finishWith)
            }
        }
    }

    private fun resultIntent() = Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)

    private suspend fun storedChoice(): String? {
        val glanceId = GlanceAppWidgetManager(this).getGlanceIdBy(appWidgetId)
        return getAppWidgetState(this, PreferencesGlanceStateDefinition, glanceId)[LiftTrendWidget.LiftKey]
    }

    /** Stores [exerciseId] for this widget (nothing when there are no lifts yet), draws the widget once, and reports success to the launcher. */
    private fun finishWith(exerciseId: String?) {
        lifecycleScope.launch {
            val glanceId = GlanceAppWidgetManager(this@LiftTrendConfigActivity).getGlanceIdBy(appWidgetId)
            if (exerciseId != null) {
                updateAppWidgetState(this@LiftTrendConfigActivity, glanceId) { it[LiftTrendWidget.LiftKey] = exerciseId }
            }
            LiftTrendWidget().update(this@LiftTrendConfigActivity, glanceId)
            setResult(RESULT_OK, resultIntent())
            finish()
        }
    }
}

/** What a row of the picker says: the lift's current estimated 1RM and how many sessions the trend rests on. */
internal fun liftPickerSummary(lift: LiftTrend): String =
    HomeText.dotted("Estimated 1RM ${HomeText.kg(lift.currentE1RM)} kg", HomeText.sessions(lift.sessionCount))

@Composable
private fun LiftPicker(lifts: List<LiftTrend>, selectedId: String?, onPick: (String?) -> Unit) {
    Scaffold(containerColor = MaterialTheme.colorScheme.background) { padding ->
        if (lifts.isEmpty()) {
            Column(
                modifier = Modifier.padding(padding).padding(24.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Text(stringResource(R.string.widget_lift_trend_config_title), style = MaterialTheme.typography.headlineSmall)
                Text(stringResource(R.string.widget_lift_trend_config_empty), style = MaterialTheme.typography.bodyLarge)
                Button(onClick = { onPick(null) }) { Text(stringResource(R.string.widget_lift_trend_config_add)) }
            }
        } else {
            // The lift a widget that is being reconfigured shows; a new widget shows the first lift until one is picked.
            val current = selectedId ?: lifts.first().exerciseID
            LazyColumn(modifier = Modifier.padding(padding)) {
                item {
                    Column(modifier = Modifier.padding(horizontal = 24.dp, vertical = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(stringResource(R.string.widget_lift_trend_config_title), style = MaterialTheme.typography.headlineSmall)
                        Text(stringResource(R.string.widget_lift_trend_config_hint), style = MaterialTheme.typography.bodyMedium)
                    }
                }
                items(lifts, key = { it.exerciseID }) { lift ->
                    ListItem(
                        modifier = Modifier.clickable { onPick(lift.exerciseID) },
                        headlineContent = { Text(lift.name) },
                        supportingContent = { Text(liftPickerSummary(lift)) },
                        trailingContent = {
                            if (lift.exerciseID == current) {
                                Icon(Icons.Filled.Check, contentDescription = stringResource(R.string.widget_lift_trend_config_selected))
                            }
                        },
                    )
                    HorizontalDivider()
                }
            }
        }
    }
}
