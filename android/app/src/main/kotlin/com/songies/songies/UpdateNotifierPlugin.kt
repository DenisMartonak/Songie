package com.songies.songies

import android.app.Activity
import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * `songies/update_notifier`, the app's side of [UpdateNotifications]:
 * - `skip` (version) keeps the background check quiet about that version;
 * - `takeOpenRequest` answers whether Songies was opened from the
 *   notification, and clears it;
 * - Dart is sent `openUpdate` when the notification is tapped while
 *   Songies is already running.
 */
class UpdateNotifierPlugin(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "songies/update_notifier")

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "skip" -> {
                    val version = call.argument<String>("version")
                    if (version != null) UpdateNotifications.setSkipped(activity.applicationContext, version)
                    result.success(null)
                }
                "takeOpenRequest" -> result.success(take(activity.intent))
                else -> result.notImplemented()
            }
        }
    }

    fun onNewIntent(intent: Intent) {
        if (take(intent)) channel.invokeMethod("openUpdate", null)
    }

    private fun take(intent: Intent?): Boolean {
        if (intent?.getBooleanExtra(UpdateNotifications.EXTRA_OPEN_UPDATE, false) != true) return false
        intent.removeExtra(UpdateNotifications.EXTRA_OPEN_UPDATE)
        return true
    }
}
