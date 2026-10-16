package health.pulse.strength.wear

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.wear.compose.material.Text

class WearMainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { Text("Pulse Strength") }
    }

    companion object {
        /** Intent extra naming a command the activity runs when it opens (only `startNext` is honoured). */
        const val EXTRA_COMMAND = "health.pulse.strength.wear.extra.COMMAND"
    }
}
