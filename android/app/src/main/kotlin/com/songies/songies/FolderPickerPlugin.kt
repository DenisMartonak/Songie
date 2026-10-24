package com.songies.songies

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * `songies/folder_picker`: `pick` opens ACTION_OPEN_DOCUMENT_TREE and answers
 * `{"path": ...}`, `{"cancelled": true}` or an error code
 * (`unsupported_location`, `no_file_manager`, `busy`, `unknown`).
 */
class FolderPickerPlugin(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    private var pending: MethodChannel.Result? = null

    init {
        MethodChannel(messenger, "songies/folder_picker").setMethodCallHandler { call, result ->
            if (call.method == "pick") pick(result) else result.notImplemented()
        }
    }

    private fun pick(result: MethodChannel.Result) {
        if (pending != null) {
            result.error("busy", "A folder picker is already open", null)
            return
        }
        try {
            pending = result
            activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE), REQUEST_CODE)
        } catch (e: ActivityNotFoundException) {
            pending = null
            result.error("no_file_manager", e.message, null)
        } catch (e: Exception) {
            pending = null
            result.error("unknown", e.toString(), null)
        }
    }

    /** Returns true when the result belonged to the folder picker. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val result = pending ?: return true
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(mapOf("cancelled" to true))
            return true
        }
        try {
            val path = pathOf(uri)
            if (path == null) {
                result.error("unsupported_location", uri.authority, null)
            } else {
                result.success(mapOf("path" to path))
            }
        } catch (e: Exception) {
            result.error("unknown", e.toString(), null)
        }
        return true
    }

    /** The file path of an external-storage tree, or null for other providers. */
    private fun pathOf(uri: Uri): String? {
        if (uri.authority != EXTERNAL_STORAGE_AUTHORITY) return null
        val docId = DocumentsContract.getTreeDocumentId(uri)
        val colon = docId.indexOf(':')
        if (colon < 0) throw IllegalArgumentException("Unexpected document id: $docId")
        val volume = docId.substring(0, colon)
        val rel = docId.substring(colon + 1).trim('/')
        val root = when (volume) {
            "primary" -> "/storage/emulated/0"
            // The picker's "Documents" root.
            "home" -> "/storage/emulated/0/Documents"
            else -> "/storage/$volume"
        }
        return if (rel.isEmpty()) root else "$root/$rel"
    }

    private companion object {
        const val REQUEST_CODE = 0x50F1
        const val EXTERNAL_STORAGE_AUTHORITY = "com.android.externalstorage.documents"
    }
}
