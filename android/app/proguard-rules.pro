# WorkManager (pulled in by ML Kit) builds its Room database by reflection.
# R8 strips the generated *_Impl classes, so the app crashed on launch in release.
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class * extends androidx.room.RoomDatabase { *; }
-keep class androidx.work.** { *; }
