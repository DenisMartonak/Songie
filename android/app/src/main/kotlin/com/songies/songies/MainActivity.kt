package com.songies.songies

import android.content.Intent
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : AudioServiceActivity() {
    private var ytDlp: YtDlpPlugin? = null
    private var share: SharePlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        ytDlp = YtDlpPlugin(applicationContext, messenger)
        share = SharePlugin(messenger, intent)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        ytDlp?.dispose()
        ytDlp = null
        share = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        share?.onNewIntent(intent)
    }
}
