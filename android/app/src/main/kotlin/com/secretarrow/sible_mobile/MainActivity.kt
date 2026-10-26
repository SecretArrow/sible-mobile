package com.secretarrow.sible_mobile

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "sible/security"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isIgnoringBatteryOptimizations" -> {
                    val pm =
                        getSystemService(Context.POWER_SERVICE) as PowerManager
                    result.success(
                        pm.isIgnoringBatteryOptimizations(packageName)
                    )
                }
                "requestIgnoreBatteryOptimizations" -> {
                    val intent = Intent(
                        Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                        Uri.parse("package:$packageName")
                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(intent)
                    result.success(true)
                }
                "getBootStartEnabled" -> {
                    // shared_preferences stores keys as `flutter.<key>` inside
                    // the `FlutterSharedPreferences` file.
                    val prefs = getSharedPreferences(
                        "FlutterSharedPreferences",
                        Context.MODE_PRIVATE
                    )
                    result.success(
                        prefs.getBoolean("flutter_security.bootStart", true)
                    )
                }
                else -> result.notImplemented()
            }
        }
    }
}
