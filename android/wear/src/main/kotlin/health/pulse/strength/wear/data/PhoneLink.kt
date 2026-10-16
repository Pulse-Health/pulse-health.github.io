package health.pulse.strength.wear.data

import android.content.Context
import android.net.Uri
import com.google.android.gms.wearable.CapabilityClient
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.Node
import com.google.android.gms.wearable.PutDataRequest
import com.google.android.gms.wearable.Wearable
import health.pulse.strength.core.widgets.WearProtocol
import health.pulse.strength.core.widgets.WidgetCommand
import health.pulse.strength.core.widgets.WidgetJson
import kotlinx.coroutines.tasks.await

/** The watch's side of the Wearable Data Layer: what [WearRuntime] needs from the phone, so tests can stand in for it. */
internal interface PhoneLink {
    /** Delivers [payload] to the phone at [path]. False when no phone is reachable. Throws on a Data Layer failure. */
    suspend fun sendMessage(path: String, payload: ByteArray): Boolean

    /** The snapshot JSON the phone last stored in the Data Layer, if any. */
    suspend fun latestSnapshotJson(): String?
}

/** The wire format of a watch to phone message (`WearProtocol.COMMAND_PATH`): the [WidgetCommand] as UTF-8 JSON. */
internal object WearCommandCodec {
    fun encode(command: WidgetCommand): ByteArray =
        WidgetJson.json.encodeToString(WidgetCommand.serializer(), command).toByteArray(Charsets.UTF_8)
}

/** [PhoneLink] over Google Play services: the phone is found by its capability, falling back to any connected node. */
internal class GmsPhoneLink(context: Context) : PhoneLink {
    private val context = context.applicationContext

    override suspend fun sendMessage(path: String, payload: ByteArray): Boolean {
        val nodeId = phoneNodeId() ?: return false
        Wearable.getMessageClient(context).sendMessage(nodeId, path, payload).await()
        return true
    }

    override suspend fun latestSnapshotJson(): String? {
        val uri = Uri.Builder().scheme(PutDataRequest.WEAR_URI_SCHEME).path(WearProtocol.SNAPSHOT_PATH).build()
        val items = Wearable.getDataClient(context).getDataItems(uri).await()
        try {
            val item = items.firstOrNull() ?: return null
            return DataMapItem.fromDataItem(item).dataMap.getString(WearProtocol.KEY_JSON)
        } finally {
            items.release()
        }
    }

    private suspend fun phoneNodeId(): String? {
        val capable = Wearable.getCapabilityClient(context)
            .getCapability(WearProtocol.PHONE_CAPABILITY, CapabilityClient.FILTER_REACHABLE)
            .await()
            .nodes
        bestNode(capable)?.let { return it.id }
        return bestNode(Wearable.getNodeClient(context).connectedNodes.await())?.id
    }

    /** A node that is nearby (directly connected) wins over one that is only reachable through the cloud. */
    private fun bestNode(nodes: Collection<Node>): Node? = nodes.firstOrNull { it.isNearby } ?: nodes.firstOrNull()
}
