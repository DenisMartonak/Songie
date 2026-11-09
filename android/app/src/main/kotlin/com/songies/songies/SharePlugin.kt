package com.songies.songies

import android.app.Activity
import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * `songies/share` + `songies/share/events`: ACTION_SEND text/plain shares
 * into the app, and `shareText` out of it (the system share menu).
 */
class SharePlugin(
    private val activity: Activity,
    messenger: BinaryMessenger,
    launchIntent: Intent?,
) {
    private var initial: String? = textOf(launchIntent)
    private var sink: EventChannel.EventSink? = null
    private val pending = ArrayDeque<String>()

    init {
        MethodChannel(messenger, "songies/share").setMethodCallHandler { call, result ->
            when (call.method) {
                "initialText" -> {
                    val t = initial
                    initial = null // consume once so recreation doesn't re-import
                    result.success(t)
                }
                "shareText" -> {
                    val send = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, call.arguments as? String)
                    }
                    activity.startActivity(Intent.createChooser(send, null))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, "songies/share/events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink) {
                    sink = events
                    while (pending.isNotEmpty()) events.success(pending.removeFirst())
                }

                override fun onCancel(args: Any?) {
                    sink = null
                }
            },
        )
    }

    fun onNewIntent(intent: Intent) {
        val t = textOf(intent) ?: return
        val s = sink
        if (s != null) s.success(t) else pending.addLast(t)
    }

    private fun textOf(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_SEND || intent.type != "text/plain") return null
        return intent.getStringExtra(Intent.EXTRA_TEXT)
    }
}
