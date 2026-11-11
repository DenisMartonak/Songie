package com.songies.songies

import android.content.Intent
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : AudioServiceActivity() {
    private var ytDlp: YtDlpPlugin? = null
    private var share: SharePlugin? = null
    private var folderPicker: FolderPickerPlugin? = null
    private var downloadNotifier: DownloadNotifierPlugin? = null
    private var updater: UpdaterPlugin? = null
    private var deviceInfo: DeviceInfoPlugin? = null
    private var updateNotifier: UpdateNotifierPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        ytDlp = YtDlpPlugin(applicationContext, messenger)
        share = SharePlugin(this, messenger, intent)
        folderPicker = FolderPickerPlugin(this, messenger)
        downloadNotifier = DownloadNotifierPlugin(applicationContext, messenger)
        updater = UpdaterPlugin(this, messenger)
        deviceInfo = DeviceInfoPlugin(messenger)
        updateNotifier = UpdateNotifierPlugin(this, messenger)
        // The background update check (SON-28); kept as is once scheduled.
        UpdateNotifications.schedule(applicationContext)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        ytDlp?.dispose()
        ytDlp = null
        share = null
        folderPicker = null
        downloadNotifier = null
        updater = null
        deviceInfo = null
        updateNotifier = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        share?.onNewIntent(intent)
        updateNotifier?.onNewIntent(intent)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        folderPicker?.onActivityResult(requestCode, resultCode, data)
        // Always forwarded, so other plugins' results (file_picker's saveFile) still arrive.
        super.onActivityResult(requestCode, resultCode, data)
    }
}
