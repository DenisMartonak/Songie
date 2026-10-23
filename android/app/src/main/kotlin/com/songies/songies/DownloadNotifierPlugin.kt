package com.songies.songies

import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * `songies/download_notifier`: `update` (title, text, progress, max) starts or
 * refreshes the foreground service; `finished` (text) stops it and posts a
 * dismissible summary; `apiLevel` answers Build.VERSION.SDK_INT.
 */
class DownloadNotifierPlugin(
    private val context: Context,
    messenger: BinaryMessenger,
) {
    init {
        MethodChannel(messenger, "songies/download_notifier").setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    update(
                        call.argument<String>("title") ?: "Downloading songs",
                        call.argument<String>("text") ?: "",
                        call.argument<Int>("progress") ?: 0,
                        call.argument<Int>("max") ?: 0,
                    )
                    result.success(null)
                }
                "finished" -> {
                    finished(call.argument<String>("text") ?: "")
                    result.success(null)
                }
                "apiLevel" -> result.success(Build.VERSION.SDK_INT)
                else -> result.notImplemented()
            }
        }
    }

    private fun update(title: String, text: String, progress: Int, max: Int) {
        NotificationManagerCompat.from(context).cancel(DownloadForegroundService.DONE_ID)
        val intent = Intent(context, DownloadForegroundService::class.java)
            .putExtra(DownloadForegroundService.EXTRA_TITLE, title)
            .putExtra(DownloadForegroundService.EXTRA_TEXT, text)
            .putExtra(DownloadForegroundService.EXTRA_PROGRESS, progress)
            .putExtra(DownloadForegroundService.EXTRA_MAX, max)
        try {
            ContextCompat.startForegroundService(context, intent)
        } catch (e: Exception) {
            // Android may refuse a foreground start from the background: show
            // the notification without the service.
            DownloadForegroundService.post(
                context,
                DownloadForegroundService.PROGRESS_ID,
                DownloadForegroundService.progressNotification(context, title, text, progress, max),
            )
        }
    }

    private fun finished(text: String) {
        context.stopService(Intent(context, DownloadForegroundService::class.java))
        // Covers the case where the service never started.
        NotificationManagerCompat.from(context).cancel(DownloadForegroundService.PROGRESS_ID)
        DownloadForegroundService.post(
            context,
            DownloadForegroundService.DONE_ID,
            DownloadForegroundService.doneNotification(context, text),
        )
    }
}
