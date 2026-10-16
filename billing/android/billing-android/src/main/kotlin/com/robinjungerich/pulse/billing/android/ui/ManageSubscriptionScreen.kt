// ManageSubscriptionScreen.kt
// Status, renewal or end date, cancel at period end / undo, and the Stripe portal for payment methods and invoices.

package com.robinjungerich.pulse.billing.android.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.robinjungerich.pulse.billing.BillingStrings
import com.robinjungerich.pulse.billing.android.BillingEvent
import com.robinjungerich.pulse.billing.android.BillingViewModel

/** The subscription screen. Refreshes the entitlement whenever it comes to the foreground, e.g. back from the portal. */
@Composable
fun ManageSubscriptionScreen(
    viewModel: BillingViewModel,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { viewModel.refreshEntitlement() }
    LaunchedEffect(viewModel) {
        viewModel.events.collect { event ->
            when (event) {
                is BillingEvent.OpenPortal -> openInCustomTab(context, event.url)
            }
        }
    }

    val state by viewModel.entitlement.collectAsStateWithLifecycle()

    ManageContent(
        model = manageModel(state, viewModel.strings),
        strings = viewModel.strings,
        onCancel = viewModel::cancelSubscription,
        onResume = viewModel::resumeSubscription,
        onManagePayments = viewModel::openPortal,
        onRetry = viewModel::refreshEntitlement,
        modifier = modifier,
    )
}

@Composable
internal fun ManageContent(
    model: ManageModel,
    strings: BillingStrings,
    onCancel: () -> Unit,
    onResume: () -> Unit,
    onManagePayments: () -> Unit,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(
            text = strings.manageTitle,
            style = MaterialTheme.typography.headlineMedium,
            modifier = Modifier.semantics { heading() },
        )
        when (model) {
            ManageModel.Loading -> Loading(strings.loadingStatus)
            is ManageModel.LoadFailed -> {
                Text(model.message, color = MaterialTheme.colorScheme.error, modifier = Modifier.politeLiveRegion())
                OutlinedButton(onClick = onRetry) { Text(strings.retry) }
            }
            is ManageModel.Loaded -> Loaded(model, strings, onCancel, onResume, onManagePayments)
        }
    }
}

@Composable
private fun Loaded(
    model: ManageModel.Loaded,
    strings: BillingStrings,
    onCancel: () -> Unit,
    onResume: () -> Unit,
    onManagePayments: () -> Unit,
) {
    var confirmingCancel by rememberSaveable { mutableStateOf(false) }

    Text(model.status, style = MaterialTheme.typography.titleLarge)
    model.details.forEach { Text(it, style = MaterialTheme.typography.bodyLarge) }
    model.notes.forEach { Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
    model.error?.let { Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.politeLiveRegion()) }

    if (model.canResume) {
        Button(onClick = onResume, enabled = !model.working, modifier = Modifier.fillMaxWidth()) { Text(strings.undoCancellation) }
    }
    if (model.canCancel) {
        OutlinedButton(onClick = { confirmingCancel = true }, enabled = !model.working, modifier = Modifier.fillMaxWidth()) {
            Text(strings.cancelSubscription)
        }
    }
    if (model.canManagePayments) {
        OutlinedButton(
            onClick = onManagePayments,
            enabled = !model.working,
            modifier = Modifier.fillMaxWidth().semantics { contentDescription = "${strings.managePayments}. ${strings.opensInBrowser}" },
        ) {
            Text(strings.managePayments)
        }
    }
    if (model.working) {
        LinearProgressIndicator(modifier = Modifier.fillMaxWidth().semantics { contentDescription = strings.loadingStatus })
    }

    if (confirmingCancel) {
        AlertDialog(
            onDismissRequest = { confirmingCancel = false },
            title = { Text(strings.cancelConfirmTitle) },
            text = { Text(strings.cancelConfirmBody(model.endDate)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        confirmingCancel = false
                        onCancel()
                    },
                ) { Text(strings.cancelSubscription) }
            },
            dismissButton = { TextButton(onClick = { confirmingCancel = false }) { Text(strings.cancelConfirmKeep) } },
        )
    }
}
