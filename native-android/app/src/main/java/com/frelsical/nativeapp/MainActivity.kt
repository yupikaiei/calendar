package com.frelsical.nativeapp

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.getValue
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.frelsical.nativeapp.external.ExternalEventIntents
import com.frelsical.nativeapp.external.ExternalEventRequest
import com.frelsical.nativeapp.notify.ReminderScheduler
import com.frelsical.nativeapp.ui.CalendarApp
import com.frelsical.nativeapp.ui.theme.FrelsiTheme
import kotlinx.coroutines.flow.MutableStateFlow

class MainActivity : ComponentActivity() {

    /** Request parsed from the launching intent, cleared once the UI handles it. */
    private val externalRequest = MutableStateFlow<ExternalEventRequest?>(null)

    private val requestNotificationPermission = registerForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { /* Reminders stay silent if the user declines; everything else keeps working. */ }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        externalRequest.value = ExternalEventIntents.parse(intent)

        setContent {
            FrelsiTheme {
                val request by externalRequest.collectAsStateWithLifecycle()
                CalendarApp(
                    externalRequest = request,
                    onExternalRequestConsumed = { externalRequest.value = null },
                )
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS,
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            requestNotificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
        ReminderScheduler.ensureChannel(this)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        ExternalEventIntents.parse(intent)?.let { externalRequest.value = it }
    }
}
