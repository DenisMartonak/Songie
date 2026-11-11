package com.songies.songies

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequest
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.TimeUnit

/**
 * The update notification (SON-28): a background job checks GitHub about every
 * 6 hours (only online), even with Songies closed, and shows "Songies X is
 * available" once per version. Tapping it opens Songies, whose usual prompt
 * downloads, checks and installs the update. The rules are in [UpdateNotifyRules].
 */
object UpdateNotifications {
    const val CHANNEL_ID = "updates"
    const val NOTIFICATION_ID = 4201
    const val EXTRA_OPEN_UPDATE = "songies.openUpdate"

    private const val WORK_NAME = "update-check"
    private const val PREFS = "songies_update_notify"
    private const val KEY_SKIPPED = "skipped"
    private const val KEY_NOTIFIED = "notified"
    private const val LATEST_URL = "https://api.github.com/repos/DenisMartonak/Songie/releases/latest"

    /** Starts the periodic check; an already scheduled one is kept as is. */
    fun schedule(context: Context) {
        val request = PeriodicWorkRequest.Builder(UpdateCheckWorker::class.java, 6, TimeUnit.HOURS)
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .build()
        WorkManager.getInstance(context)
            .enqueueUniquePeriodicWork(WORK_NAME, ExistingPeriodicWorkPolicy.KEEP, request)
    }

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** The version the in-app prompt's "Not now" skipped. */
    fun setSkipped(context: Context, version: String) {
        prefs(context).edit().putString(KEY_SKIPPED, version).apply()
    }

    /** One check: fetch the latest release and notify if the rules say so. */
    fun checkOnce(context: Context) {
        val installed = context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: return
        val (tag, assets) = UpdateNotifyRules.readRelease(fetchLatest()) ?: return
        val p = prefs(context)
        val version = UpdateNotifyRules.versionToNotify(
            tag, assets, installed, p.getString(KEY_SKIPPED, null), p.getString(KEY_NOTIFIED, null),
        ) ?: return
        if (show(context, version)) p.edit().putString(KEY_NOTIFIED, version).apply()
    }

    private fun fetchLatest(): String {
        val conn = URL(LATEST_URL).openConnection() as HttpURLConnection
        try {
            conn.connectTimeout = 10_000
            conn.readTimeout = 10_000
            conn.setRequestProperty("Accept", "application/vnd.github+json")
            conn.setRequestProperty("User-Agent", "Songies update check")
            if (conn.responseCode != 200) throw java.io.IOException("HTTP ${conn.responseCode}")
            return conn.inputStream.bufferedReader().use { it.readText() }
        } finally {
            conn.disconnect()
        }
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val channel = NotificationChannel(CHANNEL_ID, "App updates", NotificationManager.IMPORTANCE_DEFAULT)
            .apply { description = "A new version of Songies is available" }
        context.getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    /** False when notifications aren't allowed, so it is tried again next time. */
    private fun show(context: Context, version: String): Boolean {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) return false
        val manager = NotificationManagerCompat.from(context)
        if (!manager.areNotificationsEnabled()) return false
        ensureChannel(context)
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(EXTRA_OPEN_UPDATE, true)
        }
        val open = PendingIntent.getActivity(
            context, NOTIFICATION_ID, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_songies)
            .setContentTitle("Songies $version is available")
            .setContentText("Tap to update")
            .setContentIntent(open)
            .setAutoCancel(true)
            .setCategory(NotificationCompat.CATEGORY_RECOMMENDATION)
            .build()
        return try {
            manager.notify(NOTIFICATION_ID, notification)
            true
        } catch (e: SecurityException) {
            false
        }
    }
}

/** The periodic job behind [UpdateNotifications]. A failed check waits for the next run. */
class UpdateCheckWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        try {
            UpdateNotifications.checkOnce(applicationContext)
        } catch (e: Exception) {
            // Offline, rate-limited or unreadable: try again in 6 hours.
        }
        return Result.success()
    }
}
