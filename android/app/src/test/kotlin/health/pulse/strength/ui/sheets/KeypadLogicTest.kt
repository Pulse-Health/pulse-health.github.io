package health.pulse.strength.ui.sheets

import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.ExerciseLibrary
import health.pulse.strength.core.LoggedSet
import health.pulse.strength.core.PreviousSet
import health.pulse.strength.ui.KeypadField
import org.junit.Test

/** The keypad's rules without any UI. */
class KeypadLogicTest {
    private fun digit(d: String) = KeypadKey.Digit(d)

    private fun type(field: KeypadField, vararg keys: KeypadKey, start: String = "0", fresh: Boolean = true): String {
        var buffer = start
        var isFresh = fresh
        for (key in keys) {
            val next = KeypadLogic.applying(key, buffer, isFresh, field) ?: continue
            buffer = next
            isFresh = false
        }
        return buffer
    }

    @Test
    fun aFreshBufferIsReplacedByTheFirstDigit() {
        assertThat(type(KeypadField.WEIGHT, digit("7"), start = "82.5")).isEqualTo("7")
        assertThat(type(KeypadField.WEIGHT, digit("7"), digit("5"), start = "82.5")).isEqualTo("75")
    }

    @Test
    fun aZeroBufferIsReplacedToo() {
        assertThat(KeypadLogic.applying(digit("4"), "0", isFresh = false, field = KeypadField.REPS)).isEqualTo("4")
    }

    @Test
    fun decimalPointRules() {
        // Not on reps, a fresh buffer becomes "0.", never twice.
        assertThat(KeypadLogic.applying(KeypadKey.Decimal, "6", false, KeypadField.REPS)).isNull()
        assertThat(KeypadLogic.applying(KeypadKey.Decimal, "82.5", true, KeypadField.WEIGHT)).isEqualTo("0.")
        assertThat(KeypadLogic.applying(KeypadKey.Decimal, "82", false, KeypadField.WEIGHT)).isEqualTo("82.")
        assertThat(KeypadLogic.applying(KeypadKey.Decimal, "82.", false, KeypadField.WEIGHT)).isNull()
    }

    @Test
    fun weightHasAtMostTwoDecimalsAndSixCharacters() {
        assertThat(type(KeypadField.WEIGHT, digit("1"), KeypadKey.Decimal, digit("2"), digit("5"), digit("7"))).isEqualTo("1.25")
        assertThat(type(KeypadField.WEIGHT, digit("1"), digit("2"), digit("3"), digit("4"), digit("5"), digit("6"), digit("7")))
            .isEqualTo("123456")
    }

    @Test
    fun repsStayWithin999() {
        assertThat(type(KeypadField.REPS, digit("9"), digit("9"), digit("9"), digit("9"))).isEqualTo("999")
        assertThat(type(KeypadField.REPS, digit("1"), digit("0"), digit("0"), digit("0"))).isEqualTo("100")
    }

    @Test
    fun deleteRemovesOneCharacterAndNeverEmptiesTheBuffer() {
        assertThat(KeypadLogic.applying(KeypadKey.Delete, "82.5", false, KeypadField.WEIGHT)).isEqualTo("82.")
        assertThat(KeypadLogic.applying(KeypadKey.Delete, "8", false, KeypadField.WEIGHT)).isEqualTo("0")
        assertThat(KeypadLogic.applying(KeypadKey.Delete, "0", false, KeypadField.WEIGHT)).isEqualTo("0")
    }

    @Test
    fun parseNumberIsForgiving() {
        assertThat(KeypadLogic.parseNumber("82.5")).isEqualTo(82.5)
        assertThat(KeypadLogic.parseNumber("82.")).isEqualTo(82.0)
        assertThat(KeypadLogic.parseNumber("")).isEqualTo(0.0)
        assertThat(KeypadLogic.parseNumber(".")).isEqualTo(0.0)
        assertThat(KeypadLogic.parseNumber("-3")).isEqualTo(0.0)
        assertThat(KeypadLogic.parseNumber("NaN")).isEqualTo(0.0)
        assertThat(KeypadLogic.parseNumber("1e5")).isEqualTo(0.0)
        assertThat(KeypadLogic.reps("12.")).isEqualTo(12)
        assertThat(KeypadLogic.reps("5000")).isEqualTo(999)
    }

    @Test
    fun steppersUseTheExerciseStepAndStayInRange() {
        val bench = ExerciseLibrary.exercise("bench")!!
        val incline = ExerciseLibrary.exercise("incline")!!
        assertThat(KeypadLogic.stepped(1, KeypadField.WEIGHT, "82.5", bench)).isEqualTo("85")
        assertThat(KeypadLogic.stepped(-1, KeypadField.WEIGHT, "1", bench)).isEqualTo("0")
        assertThat(KeypadLogic.stepped(1, KeypadField.WEIGHT, "10", incline)).isEqualTo("12")
        assertThat(KeypadLogic.stepped(1, KeypadField.REPS, "6", bench)).isEqualTo("7")
        assertThat(KeypadLogic.stepped(-1, KeypadField.REPS, "0", bench)).isEqualTo("0")
        assertThat(KeypadLogic.stepped(1, KeypadField.REPS, "999", bench)).isEqualTo("999")
    }

    @Test
    fun durationRepsStepInFiveSeconds() {
        val plank = ExerciseLibrary.builtIn.first { it.tracking == health.pulse.strength.core.TrackingKind.DURATION }
        assertThat(KeypadLogic.stepped(1, KeypadField.REPS, "45", plank)).isEqualTo("50")
        assertThat(KeypadLogic.useLastText(KeypadField.REPS, plank, PreviousSet(0.0, 60))).isEqualTo("Use last: 60 s")
    }

    @Test
    fun previousSetIsTheSameIndexOrTheLast() {
        val bench = ExerciseLibrary.exercise("bench")!!
        assertThat(KeypadLogic.previousSet(bench, 0)).isEqualTo(PreviousSet(50.0, 8))
        assertThat(KeypadLogic.previousSet(bench, 9)).isEqualTo(PreviousSet(80.0, 5))
        assertThat(KeypadLogic.previousSet(ExerciseLibrary.exercise("cpress")!!, 0)).isNull()
    }

    @Test
    fun plateInfoNotes() {
        assertThat(KeypadLogic.plateInfo(100.0, 20.0).plates).containsExactly(25.0, 15.0).inOrder()
        assertThat(KeypadLogic.plateInfo(20.0, 20.0).note).isEqualTo("Bar only")
        assertThat(KeypadLogic.plateInfo(10.0, 20.0).note).isEqualTo("Below the bar weight")
        assertThat(KeypadLogic.plateInfo(21.0, 20.0).note).isEqualTo("+ 0.5 kg left over")
        assertThat(KeypadLogic.plateInfo(500_000.0, 20.0).note).isEqualTo("Too many plates to show")
        val speech = KeypadLogic.plateSpeech(KeypadLogic.plateInfo(82.5, 20.0), 20.0)
        assertThat(speech).isEqualTo("20 kilogram bar. 25 + 5 + 1.25 per side")
    }

    @Test
    fun primaryTitle() {
        val bench = ExerciseLibrary.exercise("bench")!!
        val pushup = ExerciseLibrary.exercise("pushup")!!
        val pending = LoggedSet(weightKg = 80.0, reps = 5)
        assertThat(KeypadLogic.primaryTitle(KeypadField.WEIGHT, bench, pending)).isEqualTo("Next: Reps")
        assertThat(KeypadLogic.primaryTitle(KeypadField.REPS, bench, pending)).isEqualTo("Log Set")
        assertThat(KeypadLogic.primaryTitle(KeypadField.REPS, bench, pending.copy(isDone = true))).isEqualTo("Done")
        assertThat(KeypadLogic.primaryTitle(KeypadField.WEIGHT, pushup, pending)).isEqualTo("Log Set")
    }
}
