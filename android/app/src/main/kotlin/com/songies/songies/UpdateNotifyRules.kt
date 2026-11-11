package com.songies.songies

import org.json.JSONObject

/** The decisions behind the update notification (SON-28), kept pure so they can be tested. */
object UpdateNotifyRules {
    /** `v1.4.2` or `1.4.2+11` as [1, 4, 2]; null unless exactly three numbers. */
    fun parse(version: String): List<Int>? {
        val core = version.trim().removePrefix("v").substringBefore('+')
        val parts = core.split('.')
        if (parts.size != 3) return null
        return parts.map { p -> p.takeIf { it.isNotEmpty() && it.all(Char::isDigit) }?.toIntOrNull() ?: return null }
    }

    private fun newer(a: List<Int>, b: List<Int>): Boolean {
        for (i in 0 until 3) if (a[i] != b[i]) return a[i] > b[i]
        return false
    }

    /**
     * The version (`1.4.2`) to notify about, or null to stay quiet: the latest
     * release [latestTag] must be newer than [installed], carry an APK among
     * [assetNames], and be neither the [skipped] version nor the one already
     * [notified].
     */
    fun versionToNotify(
        latestTag: String,
        assetNames: List<String>,
        installed: String,
        skipped: String?,
        notified: String?,
    ): String? {
        val latest = parse(latestTag) ?: return null
        val current = parse(installed) ?: return null
        if (!newer(latest, current)) return null
        if (assetNames.none { it.endsWith(".apk") }) return null
        val version = latest.joinToString(".")
        if (version == skipped || version == notified) return null
        return version
    }

    /** The tag and asset names from GitHub's latest-release JSON; null if unreadable. */
    fun readRelease(json: String): Pair<String, List<String>>? = try {
        val o = JSONObject(json)
        val assets = o.optJSONArray("assets")
        val names = (0 until (assets?.length() ?: 0)).mapNotNull { i ->
            assets!!.optJSONObject(i)?.optString("name")?.takeIf { it.isNotEmpty() }
        }
        o.optString("tag_name").takeIf { it.isNotEmpty() }?.let { it to names }
    } catch (e: Exception) {
        null
    }
}
