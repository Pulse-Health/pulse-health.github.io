package health.pulse.strength.ui.hub

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import health.pulse.strength.core.MuscleGroup
import health.pulse.strength.core.RecoveryProvider
import health.pulse.strength.ui.theme.PulseFont
import health.pulse.strength.ui.theme.PulseTheme

// "Muscle Recovery" > "View All": every muscle group with its recovery level (HubRecoveryView of StrengthHubView.swift).

@Composable
internal fun HubRecoveryScreen(recovery: RecoveryProvider, actions: HubActions, modifier: Modifier = Modifier) {
    val colors = PulseTheme.colors
    HubScreenFrame(title = "Muscle Recovery", onBack = actions.pop, modifier = modifier) { inner ->
        HubContentBox(Modifier.hubScreenPadding(inner).fillMaxSize()) { gutter ->
            Column(
                Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(start = gutter, end = gutter, top = 8.dp, bottom = hubBottomPadding(inner)),
            ) {
                Column(Modifier.fillMaxWidth().hubRowBackground()) {
                    for ((index, muscle) in HubMuscles.displayOrder.withIndex()) {
                        Box {
                            HubRecoveryRow(muscle, HubMuscles.percent(muscle, recovery))
                            if (index > 0) HubDivider(Modifier.align(Alignment.TopStart), inset = 16.dp)
                        }
                    }
                }
                Text(
                    "An estimate from the sets you log: about 48 hours for a normal session, up to 72 hours after a very hard one. " +
                        "It is a rule of thumb, not medical advice.",
                    style = PulseFont.footnote,
                    color = colors.inkSecondary,
                    modifier = Modifier.padding(start = 4.dp, end = 4.dp, top = 12.dp),
                )
            }
        }
    }
}

@Composable
private fun HubRecoveryRow(muscle: MuscleGroup, percent: Int) {
    val colors = PulseTheme.colors
    val name: @Composable () -> Unit = {
        Text(muscle.title, style = PulseFont.text(15.sp, FontWeight.SemiBold), color = colors.ink)
    }
    val level: @Composable () -> Unit = {
        Text(HubMuscles.levelTitle(percent), style = PulseFont.footnote, color = colors.inkSecondary)
    }
    val value: @Composable () -> Unit = {
        Text("$percent%", style = PulseFont.number(15.sp, FontWeight.SemiBold), color = colors.ink)
    }
    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp)
            .clearAndSetSemantics {
                contentDescription = muscle.title + " recovery"
                stateDescription = "$percent percent, " + HubMuscles.levelTitle(percent)
            },
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        // Name, level and percentage on one line; at the largest font sizes the level and the percentage move under the name.
        if (isAccessibilityText()) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                name()
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    level()
                    value()
                }
            }
        } else {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.weight(1f)) { name() }
                level()
                value()
            }
        }
        HubBar(fraction = percent / 100.0, color = colors.recoveryColor(HubMuscles.level(percent)))
    }
}
