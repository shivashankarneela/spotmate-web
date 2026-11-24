package com.spotmate.spotmate

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var permissionResult: MethodChannel.Result? = null
    private var ringtone: Ringtone? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "spotmate/device_alerts")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "notificationStatus" -> result.success(notificationStatus())
                    "requestNotifications" -> {
                        if (Build.VERSION.SDK_INT >= 33 && notificationStatus() == "default" &&
                            permissionResult == null) {
                            permissionResult = result
                            getPreferences(MODE_PRIVATE).edit().putBoolean("notificationsRequested", true).apply()
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 203)
                        } else {
                            result.success(notificationStatus())
                        }
                    }
                    "notificationSettings" -> {
                        val intent = if (Build.VERSION.SDK_INT >= 26) {
                            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        } else {
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
                        }
                        startActivity(intent)
                        result.success(null)
                    }
                    "appSettings" -> {
                        startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
                        result.success(null)
                    }
                    "playMessageSound" -> {
                        val sound = RingtoneManager.getRingtone(
                            this, RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION))
                        sound?.play()
                        result.success(true)
                    }
                    "playRingtone" -> {
                        ringtone?.stop()
                        ringtone = RingtoneManager.getRingtone(
                            this, RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE))
                        if (Build.VERSION.SDK_INT >= 28) ringtone?.isLooping = true
                        ringtone?.play()
                        result.success(true)
                    }
                    "stopRingtone" -> {
                        ringtone?.stop()
                        ringtone = null
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Suppress("DEPRECATION")
    private fun notificationStatus(): String {
        val manager = getSystemService(android.app.NotificationManager::class.java)
        if (manager.areNotificationsEnabled()) return "granted"
        if (Build.VERSION.SDK_INT < 33) return "denied"
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            return "denied"
        }
        return if (!getPreferences(MODE_PRIVATE).getBoolean("notificationsRequested", false) ||
            shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS)) "default" else "denied"
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 203) {
            permissionResult?.success(notificationStatus())
            permissionResult = null
        }
    }

    override fun onDestroy() {
        ringtone?.stop()
        super.onDestroy()
    }
}
