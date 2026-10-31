package com.songies.songies

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

/**
 * `songies/updater`: installs a downloaded, checksum-verified update APK.
 * - `inspect` (path) answers `{sameSigner, versionCode, installedVersionCode}`;
 *   an archive that can't be parsed answers `sameSigner = false`.
 * - `canInstall` answers whether "Install unknown apps" is allowed.
 * - `openInstallSettings` opens that setting for Songies.
 * - `install` (path) opens the system install screen through the
 *   `${applicationId}.updates` FileProvider (res/xml/update_paths.xml).
 */
class UpdaterPlugin(private val activity: Activity, messenger: BinaryMessenger) {
    private val main = Handler(Looper.getMainLooper())

    init {
        MethodChannel(messenger, "songies/updater").setMethodCallHandler { call, result ->
            when (call.method) {
                "inspect" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("bad_args", "path missing", null)
                    } else {
                        // Parsing and verifying a large APK takes a while.
                        Thread {
                            val answer = try {
                                inspect(path)
                            } catch (e: Throwable) {
                                // Even an OOM on this worker must not crash the app.
                                failClosed()
                            }
                            main.post { result.success(answer) }
                        }.start()
                    }
                }
                "canInstall" -> result.success(canInstall())
                "openInstallSettings" -> {
                    try {
                        openInstallSettings()
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("settings_failed", e.message, null)
                    }
                }
                "install" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("bad_args", "path missing", null)
                    } else {
                        try {
                            install(path)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("install_failed", e.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun failClosed(): Map<String, Any> =
        mapOf("sameSigner" to false, "versionCode" to 0L, "installedVersionCode" to 0L)

    private fun inspect(path: String): Map<String, Any> {
        val pm = activity.packageManager
        val installed = packageInfo(pm, activity.packageName)
        val archive = archiveInfo(pm, path) ?: return failClosed()
        val installedCode = versionCodeOf(installed)
        val mine = signerDigests(installed)
        val theirs = signerDigests(archive)
        val same = archive.packageName == activity.packageName &&
            mine.isNotEmpty() && mine == theirs
        return mapOf(
            "sameSigner" to same,
            "versionCode" to versionCodeOf(archive),
            "installedVersionCode" to installedCode,
        )
    }

    private val signerFlags: Int
        @Suppress("DEPRECATION")
        get() = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            // GET_SIGNATURES too, as a fallback where signingInfo comes back null.
            PackageManager.GET_SIGNING_CERTIFICATES or PackageManager.GET_SIGNATURES
        } else {
            PackageManager.GET_SIGNATURES
        }

    @Suppress("DEPRECATION")
    private fun packageInfo(pm: PackageManager, name: String): PackageInfo =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.getPackageInfo(name, PackageManager.PackageInfoFlags.of(signerFlags.toLong()))
        } else {
            pm.getPackageInfo(name, signerFlags)
        }

    @Suppress("DEPRECATION")
    private fun archiveInfo(pm: PackageManager, path: String): PackageInfo? {
        val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.getPackageArchiveInfo(path, PackageManager.PackageInfoFlags.of(signerFlags.toLong()))
        } else {
            pm.getPackageArchiveInfo(path, signerFlags)
        } ?: return null
        // An archive's applicationInfo has no source path; point it at the
        // file so anything read from it later resolves against the APK.
        info.applicationInfo?.let {
            it.sourceDir = path
            it.publicSourceDir = path
        }
        return info
    }

    @Suppress("DEPRECATION")
    private fun versionCodeOf(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            info.versionCode.toLong()
        }

    /** SHA-256 of every signer certificate; empty when none could be read. */
    @Suppress("DEPRECATION")
    private fun signerDigests(info: PackageInfo): Set<String> {
        var sigs: Array<Signature>? = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            sigs = info.signingInfo?.apkContentsSigners
        }
        if (sigs.isNullOrEmpty()) sigs = info.signatures
        if (sigs.isNullOrEmpty()) return emptySet()
        return sigs.map { sha256(it.toByteArray()) }.toSet()
    }

    private fun sha256(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes)
            .joinToString("") { "%02x".format(it) }

    private fun canInstall(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            activity.packageManager.canRequestPackageInstalls()
        } else {
            // Below API 26 the system install screen handles unknown sources.
            true
        }

    private fun openInstallSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:${activity.packageName}"),
            )
        } else {
            Intent(Settings.ACTION_SECURITY_SETTINGS)
        }
        activity.startActivity(intent)
    }

    private fun install(path: String) {
        val uri = FileProvider.getUriForFile(
            activity,
            "${activity.packageName}.updates",
            File(path),
        )
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        activity.startActivity(intent)
    }
}
