package com.songies.songies

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ServiceCompat

/**
 * Keeps the process alive while songs download (screen off) and shows the
 * progress notification. It only displays what [DownloadNotifierPlugin] sends;
 * audio_service's own media service and notification are separate.
 */
class DownloadForegroundService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) {
            // Restarted without data after the process died: nothing to show.
            stopSelf()
            return START_NOT_STICKY
        }
        // Every start (also a stop) must reach startForeground, or Android
        // crashes the app for a startForegroundService that never did.
        val title = intent.getStringExtra(EXTRA_TITLE) ?: "Downloading songs"
        val text = intent.getStringExtra(EXTRA_TEXT) ?: ""
        val progress = intent.getIntExtra(EXTRA_PROGRESS, 0)
        val max = intent.getIntExtra(EXTRA_MAX, 0)
        val notification = progressNotification(this, title, text, progress, max)
        val type = if (Build.VERSION.SDK_INT >= 29) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
        } else {
            0
        }
        try {
            ServiceCompat.startForeground(this, PROGRESS_ID, notification, type)
        } catch (e: Exception) {
            // Not allowed (time budget spent, background start, bad type):
            // show a plain notification and let the plugin keep it updated.
            foregroundRefused = true
            if (intent.action != ACTION_STOP) post(this, PROGRESS_ID, notification)
            stopSelf()
            return START_NOT_STICKY
        }
        if (intent.action == ACTION_STOP) {
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
        return START_NOT_STICKY
    }

    /** Android 15 ends a dataSync service after its time budget; stop cleanly. */
    override fun onTimeout(startId: Int, fgsType: Int) {
        foregroundRefused = true
        stopSelf()
    }

    override fun onDestroy() {
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    companion object {
        const val ACTION_STOP = "com.songies.songies.STOP_DOWNLOADS"

        /**
         * Set when Android refused or ended the foreground service; the plugin
         * then keeps a plain notification for the rest of the run.
         */
        @Volatile
        var foregroundRefused = false

        const val CHANNEL_ID = "downloads"
        const val PROGRESS_ID = 4101
        const val DONE_ID = 4102
        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"
        const val EXTRA_PROGRESS = "progress"
        const val EXTRA_MAX = "max"

        fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < 26) return
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Downloads",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                setSound(null, null)
                enableVibration(false)
            }
            context.getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }

        private fun openAppIntent(context: Context): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            return PendingIntent.getActivity(
                context,
                0,
                intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        }

        private fun base(context: Context, title: String, text: String): NotificationCompat.Builder {
            ensureChannel(context)
            return NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_stat_songies)
                .setContentTitle(title)
                .setContentText(text)
                .setContentIntent(openAppIntent(context))
                .setSilent(true)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setCategory(NotificationCompat.CATEGORY_PROGRESS)
        }

        fun progressNotification(
            context: Context,
            title: String,
            text: String,
            progress: Int,
            max: Int,
        ): Notification = base(context, title, text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setProgress(max, progress.coerceIn(0, max), false)
            .build()

        fun doneNotification(context: Context, text: String): Notification =
            base(context, "Downloads finished", text)
                .setAutoCancel(true)
                .setOngoing(false)
                .build()

        /** Posts [notification] when the user allows notifications; never throws. */
        @SuppressLint("MissingPermission")
        fun post(context: Context, id: Int, notification: Notification) {
            try {
                val manager = NotificationManagerCompat.from(context)
                if (manager.areNotificationsEnabled()) manager.notify(id, notification)
            } catch (_: SecurityException) {
                // POST_NOTIFICATIONS refused: downloading goes on without it.
            }
        }
    }
}
