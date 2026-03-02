package com.Android.stremini_ai

import android.content.BroadcastReceiver
import android.content.Context

/**
 * Static BroadcastReceiver for notification action buttons.
 * Forwards intents to ChatOverlayService so controls work
 * from the background without opening the app.
 */
class NotificationActionReceiver : BroadcastReceiver() {
    private val dispatcher = OverlayServiceIntentDispatcher()

    override fun onReceive(context: Context, intent: android.content.Intent?) {
        dispatcher.dispatch(context, intent?.action)
    }
}
