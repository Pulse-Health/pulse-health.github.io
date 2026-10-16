// WireSerializers.kt
// How the wire format of billing/contract/openapi.yaml maps onto Kotlin types.
//
// Two rules of the contract live here so no model has to repeat them:
//  - an enum value the client does not know decodes to the enum's UNKNOWN case instead of failing the whole
//    response (the server may add values without a version bump);
//  - timestamps are ISO-8601 instants, with or without fractional seconds.

package com.robinjungerich.pulse.billing

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerializationException
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import java.time.Instant
import java.time.OffsetDateTime
import java.time.format.DateTimeParseException

/** An enum whose JSON representation is [wire]. Every implementation has an `UNKNOWN` case for values from the future. */
interface WireEnum {
    val wire: String
}

internal abstract class WireEnumSerializer<E>(
    serialName: String,
    private val entries: List<E>,
    private val unknown: E,
) : KSerializer<E> where E : Enum<E>, E : WireEnum {

    override val descriptor: SerialDescriptor = PrimitiveSerialDescriptor(serialName, PrimitiveKind.STRING)

    override fun deserialize(decoder: Decoder): E {
        val raw = decoder.decodeString()
        return entries.firstOrNull { it !== unknown && it.wire == raw } ?: unknown
    }

    override fun serialize(encoder: Encoder, value: E) = encoder.encodeString(value.wire)
}

internal object InstantIso8601Serializer : KSerializer<Instant> {
    override val descriptor: SerialDescriptor = PrimitiveSerialDescriptor("java.time.Instant", PrimitiveKind.STRING)

    override fun deserialize(decoder: Decoder): Instant = parseInstant(decoder.decodeString())

    override fun serialize(encoder: Encoder, value: Instant) = encoder.encodeString(value.toString())
}

/** `2026-11-16T10:00:00Z`, `2026-11-16T10:00:00.250Z`, or the same with a numeric offset. */
internal fun parseInstant(text: String): Instant =
    try {
        Instant.parse(text)
    } catch (_: DateTimeParseException) {
        try {
            OffsetDateTime.parse(text).toInstant()
        } catch (e: DateTimeParseException) {
            throw SerializationException("Not an ISO-8601 instant: '$text'", e)
        }
    }

/** The one JSON configuration of the billing client: unknown fields are ignored, null fields are not sent. */
internal val BillingJson: Json = Json {
    ignoreUnknownKeys = true
    explicitNulls = false
}
