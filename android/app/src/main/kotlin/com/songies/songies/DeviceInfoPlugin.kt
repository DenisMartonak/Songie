package com.songies.songies

import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** `songies/device`: `model` answers the manufacturer and model, e.g. "Google Pixel 8". */
class DeviceInfoPlugin(messenger: BinaryMessenger) {
    init {
        MethodChannel(messenger, "songies/device").setMethodCallHandler { call, result ->
            if (call.method == "model") {
                result.success("${Build.MANUFACTURER} ${Build.MODEL}".trim())
            } else {
                result.notImplemented()
            }
        }
    }
}
