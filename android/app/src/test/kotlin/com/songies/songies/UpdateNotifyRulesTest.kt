package com.songies.songies

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class UpdateNotifyRulesTest {
    private val withApk = listOf("SHA256SUMS", "songies-1.4.2.apk", "version.json")

    @Test
    fun parsesVersions() {
        assertEquals(listOf(1, 4, 2), UpdateNotifyRules.parse("v1.4.2"))
        assertEquals(listOf(1, 4, 1), UpdateNotifyRules.parse("1.4.1+11"))
        assertNull(UpdateNotifyRules.parse("v1.4"))
        assertNull(UpdateNotifyRules.parse("nightly"))
    }

    @Test
    fun aNewerReleaseWithAnApkIsNotified() {
        assertEquals(
            "1.4.2",
            UpdateNotifyRules.versionToNotify("v1.4.2", withApk, installed = "1.4.1", skipped = null, notified = null),
        )
        // 1.10.0 is newer than 1.9.0 (numbers, not text).
        assertEquals(
            "1.10.0",
            UpdateNotifyRules.versionToNotify("v1.10.0", listOf("songies-1.10.0.apk"), "1.9.0", null, null),
        )
    }

    @Test
    fun sameOrOlderIsQuiet() {
        assertNull(UpdateNotifyRules.versionToNotify("v1.4.1", withApk, "1.4.1", null, null))
        assertNull(UpdateNotifyRules.versionToNotify("v1.4.0", withApk, "1.4.1", null, null))
    }

    @Test
    fun eachVersionIsNotifiedOnce() {
        assertNull(UpdateNotifyRules.versionToNotify("v1.4.2", withApk, "1.4.1", null, notified = "1.4.2"))
        assertEquals("1.4.3", UpdateNotifyRules.versionToNotify("v1.4.3", listOf("songies-1.4.3.apk"), "1.4.1", null, "1.4.2"))
    }

    @Test
    fun aSkippedVersionIsQuiet() {
        assertNull(UpdateNotifyRules.versionToNotify("v1.4.2", withApk, "1.4.1", skipped = "1.4.2", notified = null))
    }

    @Test
    fun noApkOrUnreadableVersionsAreQuiet() {
        assertNull(UpdateNotifyRules.versionToNotify("v1.4.2", listOf("songies-1.4.2-x86_64.AppImage"), "1.4.1", null, null))
        assertNull(UpdateNotifyRules.versionToNotify("latest", withApk, "1.4.1", null, null))
        assertNull(UpdateNotifyRules.versionToNotify("v1.4.2", withApk, "dev", null, null))
    }

    @Test
    fun readsTheGitHubAnswer() {
        val json = """{"tag_name":"v1.4.2","assets":[{"name":"songies-1.4.2.apk"},{"name":"SHA256SUMS"}]}"""
        val (tag, assets) = UpdateNotifyRules.readRelease(json)!!
        assertEquals("v1.4.2", tag)
        assertTrue("songies-1.4.2.apk" in assets)
        assertFalse(UpdateNotifyRules.readRelease("not json") != null)
    }
}
