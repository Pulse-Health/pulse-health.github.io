// PaywallScreen.kt
// The plan picker, the fine print the consumer-protection rules ask for, the withdrawal consent and the buy button.
// Colors and type come from MaterialTheme; all text comes from BillingStrings.

package com.robinjungerich.pulse.billing.android.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.robinjungerich.pulse.billing.BillingStrings
import com.robinjungerich.pulse.billing.android.BillingLinks
import com.robinjungerich.pulse.billing.android.BillingViewModel
import com.robinjungerich.pulse.billing.android.rememberStripePaymentSheetPresenter

/**
 * The paywall. Binds the Stripe sheet to the view model's presenter, loads the offers once, and draws
 * [PaywallModel]. [onClose] is called by the "Done" button after a purchase.
 */
@Composable
fun PaywallScreen(
    viewModel: BillingViewModel,
    modifier: Modifier = Modifier,
    onClose: () -> Unit = {},
) {
    viewModel.paymentSheet?.let { rememberStripePaymentSheetPresenter(it) }
    LaunchedEffect(viewModel) { viewModel.loadOffers() }

    val state by viewModel.purchaseState.collectAsStateWithLifecycle()
    val offers by viewModel.offers.collectAsStateWithLifecycle()
    val context = LocalContext.current

    PaywallContent(
        model = paywallModel(state, offers, viewModel.strings),
        strings = viewModel.strings,
        links = viewModel.links,
        onBuy = viewModel::purchase,
        onRetry = viewModel::loadOffers,
        onOpenUrl = { openInCustomTab(context, it) },
        onDone = {
            viewModel.resetPurchase()
            onClose()
        },
        modifier = modifier,
    )
}

@Composable
internal fun PaywallContent(
    model: PaywallModel,
    strings: BillingStrings,
    links: BillingLinks,
    onBuy: (planId: String, consentGiven: Boolean) -> Unit,
    onRetry: () -> Unit,
    onOpenUrl: (String) -> Unit,
    onDone: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(
            text = strings.paywallTitle,
            style = MaterialTheme.typography.headlineMedium,
            modifier = Modifier.semantics { heading() },
        )
        when (model) {
            PaywallModel.Loading -> Loading(strings.loadingOffers)
            is PaywallModel.LoadFailed -> {
                Text(model.message, color = MaterialTheme.colorScheme.error, modifier = Modifier.politeLiveRegion())
                OutlinedButton(onClick = onRetry) { Text(strings.retry) }
            }
            is PaywallModel.Unavailable -> Text(model.message, style = MaterialTheme.typography.bodyLarge)
            is PaywallModel.Finished -> {
                Text(model.message, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.politeLiveRegion())
                Button(onClick = onDone, modifier = Modifier.fillMaxWidth()) { Text(strings.done) }
            }
            is PaywallModel.Plans -> Plans(model, strings, links, onBuy, onOpenUrl)
        }
    }
}

@Composable
private fun Plans(
    model: PaywallModel.Plans,
    strings: BillingStrings,
    links: BillingLinks,
    onBuy: (planId: String, consentGiven: Boolean) -> Unit,
    onOpenUrl: (String) -> Unit,
) {
    var selectedId by rememberSaveable { mutableStateOf<String?>(null) }
    var consent by rememberSaveable { mutableStateOf(false) }
    val selected = model.items.firstOrNull { it.id == selectedId } ?: model.items.first()
    val canBuy = !model.busy && (!model.requiresConsent || consent)

    Text(strings.choosePlan, style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        model.items.forEach { item ->
            PlanRow(item, selected = item.id == selected.id, enabled = !model.busy, onSelect = { selectedId = item.id })
        }
    }

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        selected.notes.forEach { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
    }

    Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        LinkText(strings.termsLink, strings.opensInBrowser) { onOpenUrl(links.termsUrl) }
        LinkText(strings.privacyLink, strings.opensInBrowser) { onOpenUrl(links.privacyUrl) }
    }

    if (model.requiresConsent) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .toggleable(value = consent, enabled = !model.busy, role = Role.Checkbox, onValueChange = { consent = it }),
            verticalAlignment = Alignment.Top,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Checkbox(checked = consent, onCheckedChange = null)
            Text(strings.withdrawalConsent, style = MaterialTheme.typography.bodyMedium)
        }
    }

    Button(
        onClick = { onBuy(selected.id, consent) },
        enabled = canBuy,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Text(strings.buyButton)
    }
    if (model.requiresConsent && !consent && !model.busy) {
        Text(strings.consentRequiredHint, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }

    model.progress?.let { progress ->
        Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.politeLiveRegion()) {
            LinearProgressIndicator(modifier = Modifier.fillMaxWidth().semantics { contentDescription = progress })
            Text(progress, style = MaterialTheme.typography.bodyMedium)
        }
    }
    model.banner?.let { banner ->
        Text(
            text = banner,
            style = MaterialTheme.typography.bodyMedium,
            color = if (model.bannerIsError) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.politeLiveRegion(),
        )
    }
}

@Composable
private fun PlanRow(item: PlanItem, selected: Boolean, enabled: Boolean, onSelect: () -> Unit) {
    val colors = MaterialTheme.colorScheme
    OutlinedCard(
        modifier = Modifier
            .fillMaxWidth()
            .selectable(selected = selected, enabled = enabled, role = Role.RadioButton, onClick = onSelect),
        border = BorderStroke(if (selected) 2.dp else 1.dp, if (selected) colors.primary else colors.outlineVariant),
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            RadioButton(selected = selected, onClick = null, enabled = enabled)
            Column(modifier = Modifier.weight(1f)) {
                Text(item.title, style = MaterialTheme.typography.titleMedium)
                Text(item.priceLine, style = MaterialTheme.typography.bodyMedium)
                item.trialBadge?.let { Text(it, style = MaterialTheme.typography.labelMedium, color = colors.primary) }
            }
        }
    }
}

@Composable
private fun LinkText(text: String, onClickLabel: String, onClick: () -> Unit) {
    Text(
        text = text,
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.primary,
        textDecoration = TextDecoration.Underline,
        modifier = Modifier
            .clickable(onClickLabel = onClickLabel, role = Role.Button, onClick = onClick)
            .padding(vertical = 12.dp),
    )
}

@Composable
internal fun Loading(description: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.politeLiveRegion()) {
        CircularProgressIndicator(modifier = Modifier.semantics { contentDescription = description })
        Text(description)
    }
}

internal fun Modifier.politeLiveRegion(): Modifier = semantics { liveRegion = LiveRegionMode.Polite }
