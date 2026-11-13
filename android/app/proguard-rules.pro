# Release builds are shrunk by R8 (the Flutter Gradle plugin enables minify
# for release and picks up this file automatically). youtubedl-android ships
# no consumer rules, so keep what it reaches by name or reflection.

# youtubedl-android (io.github.junkfood02.youtubedl-android:library/common;
# all classes live under com.yausername.*). Its mapper classes are filled by
# Jackson through reflection.
-keep class com.yausername.** { *; }

# Jackson (used by youtubedl-android's mapper and updater).
-keepattributes Signature,*Annotation*,InnerClasses,EnclosingMethod
-keep class com.fasterxml.jackson.** { *; }
-dontwarn com.fasterxml.jackson.**

# commons-compress unpacks the bundled Python/yt-dlp zips on first run.
-keep class org.apache.commons.compress.archivers.zip.** { *; }
-dontwarn org.apache.commons.compress.**

# Room (used by WorkManager, the background update check) creates a database
# with `Class.getDeclaredConstructor()` on the generated `*_Impl` class, so R8
# sees no caller and removed the no-argument constructor: 1.5.0 crashed at
# launch with NoSuchMethodException: WorkDatabase_Impl.<init> [].
-keep class * extends androidx.room.RoomDatabase { <init>(); }
