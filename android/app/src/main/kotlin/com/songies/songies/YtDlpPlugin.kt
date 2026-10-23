package com.songies.songies

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLException
import com.yausername.youtubedl_android.YoutubeDLRequest
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * `songies/ytdlp`: yt-dlp via youtubedl-android. Everything runs on a worker
 * thread; init happens lazily on first use.
 */
class YtDlpPlugin(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "songies/ytdlp")
    private val workers = Executors.newCachedThreadPool()
    private val main = Handler(Looper.getMainLooper())
    private val initLock = Any()
    private var initError: String? = null
    private var initialised = false

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        workers.shutdown()
    }

    /** Returns null when ready, else the init failure message. */
    private fun ensureInit(): String? = synchronized(initLock) {
        if (initialised) return null
        try {
            YoutubeDL.getInstance().init(context.applicationContext)
            initialised = true
            initError = null
        } catch (e: Throwable) {
            initError = e.message ?: e.toString()
        }
        initError
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "run" -> {
                val args = call.argument<List<String>>("args") ?: emptyList()
                val processId = call.argument<String>("processId")
                async(result) { runYtDlp(args, processId) }
            }
            "version" -> async(result) {
                ensureInit()?.let { return@async null }
                YoutubeDL.version(context.applicationContext)
            }
            "update" -> async(result) {
                ensureInit()?.let { throw UpdateFailure(it) }
                val status = try {
                    YoutubeDL.getInstance().updateYoutubeDL(
                        context.applicationContext,
                        YoutubeDL.UpdateChannel.STABLE,
                    )
                } catch (e: Exception) {
                    throw UpdateFailure(e.message ?: "yt-dlp update failed")
                }
                status?.name ?: "UNKNOWN"
            }
            "cancel" -> {
                call.argument<String>("processId")?.let {
                    try {
                        YoutubeDL.getInstance().destroyProcessById(it)
                    } catch (_: Throwable) {
                    }
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private class UpdateFailure(message: String) : Exception(message)

    private fun runYtDlp(args: List<String>, processId: String?): Map<String, Any> {
        ensureInit()?.let { throw InitFailure(it) }
        // addCommands appends the args verbatim and in order (addOption would
        // key them in a map and lose option/value pairing).
        val request = YoutubeDLRequest(emptyList<String>()).addCommands(args)
        return try {
            val r = YoutubeDL.getInstance().execute(request, processId, null)
            mapOf("exitCode" to r.exitCode, "out" to r.out, "err" to r.err)
        } catch (e: YoutubeDLException) {
            // yt-dlp exited non-zero; the message is its stderr.
            mapOf("exitCode" to 1, "out" to "", "err" to (e.message ?: ""))
        } catch (e: YoutubeDL.CanceledException) {
            mapOf("exitCode" to -1, "out" to "", "err" to "yt-dlp was cancelled")
        }
    }

    private class InitFailure(message: String) : Exception(message)

    private fun async(result: MethodChannel.Result, block: () -> Any?) {
        workers.execute {
            try {
                val v = block()
                main.post { result.success(v) }
            } catch (e: InitFailure) {
                main.post { result.error("init_failed", e.message, null) }
            } catch (e: UpdateFailure) {
                main.post { result.error("update_failed", e.message, null) }
            } catch (e: Throwable) {
                main.post { result.error("ytdlp_error", e.message ?: e.toString(), null) }
            }
        }
    }
}
