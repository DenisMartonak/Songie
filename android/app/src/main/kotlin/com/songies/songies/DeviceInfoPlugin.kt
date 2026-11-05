package com.songies.songies

import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * `songies/device`: `info` answers a map with the manufacturer and model
 * ("Google Pixel 8"), the Android release ("14") and the API level (34).
 */
class DeviceInfoPlugin(messenger: BinaryMessenger) {
    init {
        MethodChannel(messenger, "songies/device").setMethodCallHandler { call, result ->
            if (call.method == "info") {
                result.success(
                    mapOf(
                        "model" to "${Build.MANUFACTURER} ${Build.MODEL}".trim(),
                        "release" to Build.VERSION.RELEASE,
                        "sdk" to Build.VERSION.SDK_INT,
                    ),
                )
            } else {
                result.notImplemented()
            }
        }
    }
}
