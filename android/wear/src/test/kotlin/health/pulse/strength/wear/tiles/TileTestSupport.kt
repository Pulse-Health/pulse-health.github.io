package health.pulse.strength.wear.tiles

import android.content.Context
import androidx.wear.protolayout.DeviceParametersBuilders
import androidx.wear.protolayout.LayoutElementBuilders.LayoutElement
import androidx.wear.protolayout.TimelineBuilders
import androidx.wear.protolayout.proto.LayoutElementProto
import androidx.wear.protolayout.proto.ModifiersProto
import androidx.wear.tiles.TileBuilders.Tile

/** A round 200 x 200 dp watch at 2x density, the size the layouts are checked at. */
internal fun deviceParameters(widthDp: Int = 200, heightDp: Int = 200, density: Float = 2f): DeviceParametersBuilders.DeviceParameters =
    DeviceParametersBuilders.DeviceParameters.Builder()
        .setScreenWidthDp(widthDp)
        .setScreenHeightDp(heightDp)
        .setScreenDensity(density)
        .setScreenShape(DeviceParametersBuilders.SCREEN_SHAPE_ROUND)
        .setDevicePlatform(DeviceParametersBuilders.DEVICE_PLATFORM_WEAR_OS)
        .build()

internal fun tileUi(context: Context, widthDp: Int = 200, heightDp: Int = 200): TileUi = TileUi(context, deviceParameters(widthDp, heightDp))

internal fun LayoutElement.inspect() = LayoutInspector(this)

/** The layouts of a tile's timeline in order, each with the interval it is valid in (null: always). */
internal fun TilePlan.entries(): List<Pair<TimelineBuilders.TimeInterval?, LayoutElement>> =
    timeline.timelineEntries.map { entry -> entry.validity to checkNotNull(entry.layout?.root) { "a timeline entry without a layout" } }

/** The entries of the timeline of a tile (every tile of the app has one). */
internal fun Tile.timelineEntries(): List<TimelineBuilders.TimelineEntry> =
    checkNotNull(tileTimeline) { "the tile has no timeline" }.timelineEntries

/**
 * Reads a layout the way the renderer would: depth first, an element's own clickable before those of its children, so that
 * [clicks] lists the clickables in the order the double-tap gesture of Wear OS 5 walks them.
 */
internal class LayoutInspector(root: LayoutElement) {
    enum class Kind { LOAD, LAUNCH, OTHER }

    data class Click(val id: String, val kind: Kind, val className: String? = null, val extras: Map<String, String> = emptyMap())

    /** A text with the static value it shows until its dynamic value takes over (if it has one). */
    data class TextInfo(val value: String, val isDynamic: Boolean)

    val texts = mutableListOf<TextInfo>()
    val clicks = mutableListOf<Click>()
    val images = mutableListOf<String>()
    val descriptions = mutableListOf<String>()
    val boxBackgrounds = mutableListOf<Int>()

    val textValues: List<String> get() = texts.map { it.value }

    init {
        walk(root.toLayoutElementProto())
    }

    private fun walk(element: LayoutElementProto.LayoutElement) {
        when {
            element.hasColumn() -> {
                modifiers(element.column.modifiers)
                element.column.contentsList.forEach(::walk)
            }
            element.hasRow() -> {
                modifiers(element.row.modifiers)
                element.row.contentsList.forEach(::walk)
            }
            element.hasBox() -> {
                modifiers(element.box.modifiers)
                element.box.contentsList.forEach(::walk)
            }
            element.hasSpacer() -> modifiers(element.spacer.modifiers)
            element.hasText() -> {
                modifiers(element.text.modifiers)
                texts += TextInfo(element.text.text.value, element.text.text.hasDynamicValue())
            }
            element.hasImage() -> {
                modifiers(element.image.modifiers)
                images += element.image.resourceId.value
            }
            else -> Unit
        }
    }

    private fun modifiers(modifiers: ModifiersProto.Modifiers) {
        if (modifiers.hasClickable()) clicks += click(modifiers.clickable)
        if (modifiers.hasSemantics() && modifiers.semantics.hasContentDescription()) {
            descriptions += modifiers.semantics.contentDescription.value
        }
        if (modifiers.hasBackground() && modifiers.background.hasColor()) boxBackgrounds += modifiers.background.color.argb
    }

    private fun click(clickable: ModifiersProto.Clickable): Click {
        val action = clickable.onClick
        return when {
            action.hasLoadAction() -> Click(clickable.id, Kind.LOAD)
            action.hasLaunchAction() -> {
                val activity = action.launchAction.androidActivity
                val extras = activity.keyToExtraMap.mapValues { (_, extra) -> extra.stringVal.value }
                Click(clickable.id, Kind.LAUNCH, activity.className, extras)
            }
            else -> Click(clickable.id, Kind.OTHER)
        }
    }
}
