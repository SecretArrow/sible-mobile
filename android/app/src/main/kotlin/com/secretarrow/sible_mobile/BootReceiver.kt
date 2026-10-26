package com.secretarrow.sible_mobile

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Relaunches the app UI after BOOT_COMPLETED / QUICKBOOT_POWERON so the
 * Flutter bootstrap (main -> configureBackgroundService with
 * autoStartOnBoot) brings the mining worker back up. This is the reliable
 * cross-version approach for flutter_background_service 5.x: instead of
 * poking the service directly, the launcher intent restarts the whole app.
 *
 * Guarded by the persisted `security.bootStart` preference, read from the
 * `FlutterSharedPreferences` file where shared_preferences prefixes keys
 * with `flutter.`.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (
            action != Intent.ACTION_BOOT_COMPLETED &&
            action != "android.intent.action.QUICKBOOT_POWERON"
        ) {
            return
        }
        val prefs = context.getSharedPreferences(
            "FlutterSharedPreferences",
            Context.MODE_PRIVATE
        )
        if (!prefs.getBoolean("flutter_security.bootStart", true)) return
        val launch = context.packageManager
            .getLaunchIntentForPackage(context.packageName) ?: return
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            context.startActivity(launch)
        } catch (e: Exception) {
            Log.w("BootReceiver", "Could not relaunch app after boot", e)
        }
    }
}
