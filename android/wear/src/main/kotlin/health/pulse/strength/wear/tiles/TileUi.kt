package health.pulse.strength.wear.tiles

import android.content.Context
import androidx.wear.protolayout.ActionBuilders
import androidx.wear.protolayout.ColorBuilders.argb
import androidx.wear.protolayout.DeviceParametersBuilders.DeviceParameters
import androidx.wear.protolayout.DimensionBuilders.dp
import androidx.wear.protolayout.DimensionBuilders.expand
import androidx.wear.protolayout.DimensionBuilders.wrap
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.LayoutElementBuilders.LayoutElement
import androidx.wear.protolayout.ModifiersBuilders
import androidx.wear.protolayout.ResourceBuilders
import androidx.wear.protolayout.material.Button
import androidx.wear.protolayout.material.ButtonColors
import androidx.wear.protolayout.material.Chip
import androidx.wear.protolayout.material.ChipColors
import androidx.wear.protolayout.material.Colors
import androidx.wear.protolayout.material.Text
import androidx.wear.protolayout.material.Typography
import androidx.wear.protolayout.material.layouts.PrimaryLayout
import health.pulse.strength.wear.R
import health.pulse.strength.wear.WearMainActivity

/** The tiles are always dark (the watch is an OLED); these are the dark values of the canvas (widgets/SPEC.md section 7). */
internal object TileColors {
    const val GREEN = 0xFF30D158.toInt()
    const val ON_GREEN = 0xFF000000.toInt()
    const val INK = 0xFFFFFFFF.toInt()
    const val SECONDARY = 0xFF98989D.toInt()
    const val SURFACE = 0xFF1C1C1E.toInt()
    const val TRACK = 0xFF3A3A3C.toInt()
    const val GOLD = 0xFFFFD60A.toInt()
    const val HEART = 0xFFFF453A.toInt()

    /** The palette the Material tile components derive their chip, button and progress colours from. */
    val material = Colors(GREEN, ON_GREEN, SURFACE, INK)
}

/** The drawables a tile layout refers to by id; every tile ships all of them (they are only resource ids). */
internal object TileIcons {
    const val PLAY = "ic_play"
    const val HAND = "ic_hand"
    const val DUMBBELL = "ic_dumbbell"
    const val TROPHY = "ic_trophy"
    const val HEART = "ic_heart"

    /** Version of the static resources; bump when a drawable changes. */
    const val VERSION = "1"

    private val drawables = mapOf(
        PLAY to R.drawable.ic_play,
        HAND to R.drawable.ic_hand,
        DUMBBELL to R.drawable.ic_dumbbell,
        TROPHY to R.drawable.ic_trophy,
        HEART to R.drawable.ic_heart,
    )

    fun resources(version: String = VERSION): ResourceBuilders.Resources.Builder {
        val builder = ResourceBuilders.Resources.Builder().setVersion(version)
        drawables.forEach { (id, drawable) ->
            builder.addIdToImageMapping(
                id,
                ResourceBuilders.ImageResource.Builder()
                    .setAndroidResourceByResId(ResourceBuilders.AndroidImageResourceByResId.Builder().setResourceId(drawable).build())
                    .build(),
            )
        }
        return builder
    }
}

/** How a chip is coloured: green with black text for the main action, dark grey with white text for the others. */
internal enum class ChipStyle { PRIMARY, SECONDARY }

/**
 * Builds the pieces every tile layout is made of, with the Material tile components ([PrimaryLayout], [Chip], [Text]) so that margins,
 * touch targets and round-screen insets follow the platform. One instance per layout: all clickables of a layout share its generation.
 */
internal class TileUi(val context: Context, val device: DeviceParameters) {
    val generation: String = TileClicks.newGeneration()

    /** A line of text; [typography] is a `Typography.TYPOGRAPHY_*` constant. */
    fun text(
        text: String,
        typography: Int,
        color: Int,
        maxLines: Int = 1,
        bold: Boolean = false,
    ): LayoutElement = Text.Builder(context, text)
        .setTypography(typography)
        .setColor(argb(color))
        .setMaxLines(maxLines)
        .setOverflow(LayoutElementBuilders.TEXT_OVERFLOW_ELLIPSIZE)
        .setMultilineAlignment(LayoutElementBuilders.TEXT_ALIGN_CENTER)
        .setWeight(if (bold) LayoutElementBuilders.FONT_WEIGHT_BOLD else LayoutElementBuilders.FONT_WEIGHT_NORMAL)
        .build()

    /** A tinted drawable from [TileIcons], [size] dp square. */
    fun icon(id: String, size: Float, tint: Int): LayoutElement = LayoutElementBuilders.Image.Builder()
        .setResourceId(id)
        .setWidth(dp(size))
        .setHeight(dp(size))
        .setColorFilter(LayoutElementBuilders.ColorFilter.Builder().setTint(argb(tint)).build())
        .build()

    /** The small label above the content: [text] in [color], with an optional [icon] in front. */
    fun label(text: String, color: Int, typography: Int, icon: String? = null): LayoutElement {
        val line = text(text, typography, color, bold = true)
        if (icon == null) return line
        return LayoutElementBuilders.Row.Builder()
            .setWidth(wrap())
            .setHeight(wrap())
            .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
            .addContent(icon(icon, ICON_SIZE, color))
            .addContent(spacer(width = 4f))
            .addContent(line)
            .build()
    }

    fun spacer(width: Float = 0f, height: Float = 0f): LayoutElement = LayoutElementBuilders.Spacer.Builder()
        .setWidth(dp(width))
        .setHeight(dp(height))
        .build()

    /** Centres [items] one under the other. */
    fun column(vararg items: LayoutElement): LayoutElement {
        val column = LayoutElementBuilders.Column.Builder()
            .setWidth(wrap())
            .setHeight(wrap())
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
        items.forEach { column.addContent(it) }
        return column.build()
    }

    /** A clickable that asks the tile service for a new tile with its id, so the service can run [action] (see [TileClicks]). */
    fun loadClickable(action: String): ModifiersBuilders.Clickable = ModifiersBuilders.Clickable.Builder()
        .setId(TileClicks.clickableId(action, generation))
        .setOnClick(ActionBuilders.LoadAction.Builder().build())
        .build()

    /** A clickable that opens the watch app, optionally asking it to run [command] (only `startNext` is honoured, see `WearMainActivity`). */
    fun launchClickable(action: String, command: String? = null): ModifiersBuilders.Clickable {
        val activity = ActionBuilders.AndroidActivity.Builder()
            .setPackageName(context.packageName)
            .setClassName(WearMainActivity::class.java.name)
        if (command != null) activity.addKeyToExtraMapping(WearMainActivity.EXTRA_COMMAND, ActionBuilders.stringExtra(command))
        return ModifiersBuilders.Clickable.Builder()
            .setId(action)
            .setOnClick(ActionBuilders.LaunchAction.Builder().setAndroidActivity(activity.build()).build())
            .build()
    }

    /** A full-width pill, 52 dp high (Material's chip size, above the 48 dp touch target). */
    fun chip(
        label: String,
        description: String,
        clickable: ModifiersBuilders.Clickable,
        style: ChipStyle = ChipStyle.PRIMARY,
        icon: String? = null,
        width: Float? = null,
    ): LayoutElement {
        val chip = Chip.Builder(context, clickable, device)
            .setPrimaryLabelContent(label)
            .setContentDescription(description)
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .setChipColors(
                if (style == ChipStyle.PRIMARY) ChipColors.primaryChipColors(TileColors.material)
                else ChipColors.secondaryChipColors(TileColors.material),
            )
        if (icon != null) chip.setIconContent(icon)
        if (width != null) chip.setWidth(dp(width))
        return chip.build()
    }

    /** [items] side by side with [gap] dp between them, centred vertically. */
    fun row(gap: Float, vararg items: LayoutElement): LayoutElement {
        val row = LayoutElementBuilders.Row.Builder()
            .setWidth(wrap())
            .setHeight(wrap())
            .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
        items.forEachIndexed { index, item ->
            if (index > 0) row.addContent(spacer(width = gap))
            row.addContent(item)
        }
        return row.build()
    }

    /** A round button, [size] dp across, with a short text on it. */
    fun roundButton(
        label: String,
        description: String,
        clickable: ModifiersBuilders.Clickable,
        style: ChipStyle = ChipStyle.SECONDARY,
        size: Float = ROUND_BUTTON_SIZE,
    ): LayoutElement = Button.Builder(context, clickable)
        .setTextContent(label, Typography.TYPOGRAPHY_CAPTION1)
        .setContentDescription(description)
        .setSize(dp(size))
        .setButtonColors(
            if (style == ChipStyle.PRIMARY) ButtonColors.primaryButtonColors(TileColors.material)
            else ButtonColors.secondaryButtonColors(TileColors.material),
        )
        .build()

    /**
     * The standard tile page: a [label] on top, the [content] in the middle, an optional [secondary] line under it and a [chip] at the
     * bottom (everything but the content is optional).
     */
    fun screen(
        content: LayoutElement,
        label: LayoutElement? = null,
        secondary: LayoutElement? = null,
        chip: LayoutElement? = null,
    ): LayoutElement {
        val layout = PrimaryLayout.Builder(device)
            .setResponsiveContentInsetEnabled(true)
            .setContent(content)
        if (label != null) layout.setPrimaryLabelTextContent(label)
        if (secondary != null) layout.setSecondaryLabelTextContent(secondary)
        if (chip != null) layout.setPrimaryChipContent(chip)
        return layout.build()
    }

    /**
     * A page that only says something, with an "Open" chip: the "waiting for your phone" state and the empty states of every tile.
     * The [label] carries the tile's [icon] in its [accent] colour.
     */
    fun message(
        label: String,
        title: String,
        hint: String,
        icon: String = TileIcons.DUMBBELL,
        accent: Int = TileColors.GREEN,
    ): LayoutElement = screen(
        label = label(label, accent, Typography.TYPOGRAPHY_CAPTION1, icon),
        content = column(
            text(title, Typography.TYPOGRAPHY_TITLE3, TileColors.INK, maxLines = 2, bold = true),
            text(hint, Typography.TYPOGRAPHY_CAPTION2, TileColors.SECONDARY, maxLines = 2),
        ),
        chip = chip("Open", "Open Pulse Strength", launchClickable(ACTION_OPEN), ChipStyle.SECONDARY),
    )

    /**
     * Wraps [element] so that it fills the tile, reads as [description] to a screen reader and, if given, reacts to a tap anywhere.
     * [background] tints the whole tile (the record card).
     */
    fun root(
        element: LayoutElement,
        description: String,
        clickable: ModifiersBuilders.Clickable? = null,
        background: Int? = null,
    ): LayoutElement {
        val modifiers = ModifiersBuilders.Modifiers.Builder()
            .setSemantics(ModifiersBuilders.Semantics.Builder().setContentDescription(description).build())
        if (clickable != null) modifiers.setClickable(clickable)
        if (background != null) modifiers.setBackground(ModifiersBuilders.Background.Builder().setColor(argb(background)).build())
        return LayoutElementBuilders.Box.Builder()
            .setWidth(expand())
            .setHeight(expand())
            .setModifiers(modifiers.build())
            .addContent(element)
            .build()
    }

    companion object {
        /** Id of the clickable that opens the watch app. */
        const val ACTION_OPEN = "open"
        private const val ICON_SIZE = 14f
        private const val ROUND_BUTTON_SIZE = 52f
    }
}
