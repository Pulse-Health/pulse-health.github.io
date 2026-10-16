package health.pulse.strength.wear.sync

import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.WearableListenerService
import health.pulse.strength.core.widgets.WearProtocol

/**
 * Receives the snapshot the phone writes to the Data Layer (`WearProtocol.SNAPSHOT_PATH`, registered in the manifest) and hands its JSON to
 * [SnapshotIngest]. The system starts this service for a change even when the watch app is not running.
 */
class WearSnapshotListenerService : WearableListenerService() {
    override fun onDataChanged(dataEvents: DataEventBuffer) {
        handle(dataEvents)
    }

    /** The JSON of every changed snapshot item among [events], applied in order. */
    internal fun handle(events: Iterable<DataEvent>) {
        for (event in events) {
            if (event.type != DataEvent.TYPE_CHANGED) continue
            val item = event.dataItem
            if (item.uri.path != WearProtocol.SNAPSHOT_PATH) continue
            val json = DataMapItem.fromDataItem(item).dataMap.getString(WearProtocol.KEY_JSON)
            SnapshotIngest.accept(this, json)
        }
    }
}
