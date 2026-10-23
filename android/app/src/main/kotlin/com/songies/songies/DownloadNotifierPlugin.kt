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

    /** A start intent was sent and no stop has followed. */
    private var serviceStarted = false

    private fun update(title: String, text: String, progress: Int, max: Int) {
        NotificationManagerCompat.from(context).cancel(DownloadForegroundService.DONE_ID)
        if (!DownloadForegroundService.foregroundRefused) {
            val intent = Intent(context, DownloadForegroundService::class.java)
                .putExtra(DownloadForegroundService.EXTRA_TITLE, title)
                .putExtra(DownloadForegroundService.EXTRA_TEXT, text)
                .putExtra(DownloadForegroundService.EXTRA_PROGRESS, progress)
                .putExtra(DownloadForegroundService.EXTRA_MAX, max)
            try {
                ContextCompat.startForegroundService(context, intent)
                serviceStarted = true
                return
            } catch (e: Exception) {
                // Refused (e.g. a background start): plain notifications for
                // the rest of the run instead of retrying every update.
                DownloadForegroundService.foregroundRefused = true
            }
        }
        DownloadForegroundService.post(
            context,
            DownloadForegroundService.PROGRESS_ID,
            DownloadForegroundService.progressNotification(context, title, text, progress, max),
        )
    }

    private fun finished(text: String) {
        if (serviceStarted) {
            // Through the service, so the stop is delivered after the start
            // intent and its startForeground (stopService could beat it).
            val stop = Intent(context, DownloadForegroundService::class.java)
                .setAction(DownloadForegroundService.ACTION_STOP)
            try {
                ContextCompat.startForegroundService(context, stop)
            } catch (e: Exception) {
                context.stopService(Intent(context, DownloadForegroundService::class.java))
            }
        }
        serviceStarted = false
        DownloadForegroundService.foregroundRefused = false
        NotificationManagerCompat.from(context).cancel(DownloadForegroundService.PROGRESS_ID)
        DownloadForegroundService.post(
            context,
            DownloadForegroundService.DONE_ID,
            DownloadForegroundService.doneNotification(context, text),
        )
    }
}
