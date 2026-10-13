package com.pk1codes.worky

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  private val channelName = "worky/permissions"
  private var pending: MethodChannel.Result? = null
  private val reqCode = 4401

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "requestSetup" -> requestSetup(result)
          else -> result.notImplemented()
        }
      }
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "worky/heads")
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "show" -> showHeads(call.argument<String>("body") ?: "", result)
          else -> result.notImplemented()
        }
      }
  }

  private fun showHeads(body: String, result: MethodChannel.Result) {
    if (Build.VERSION.SDK_INT >= 33 &&
      ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
      PackageManager.PERMISSION_GRANTED
    ) {
      result.success(false)
      return
    }
    val manager = getSystemService(NotificationManager::class.java)
    if (Build.VERSION.SDK_INT >= 26) {
      manager.createNotificationChannel(
        NotificationChannel("worky", "Worky", NotificationManager.IMPORTANCE_HIGH),
      )
    }
    val launch = packageManager.getLaunchIntentForPackage(packageName)
    val note = NotificationCompat.Builder(this, "worky")
      .setSmallIcon(R.drawable.ic_stat_worky)
      .setContentTitle("Worky")
      .setContentText(body)
      .setPriority(NotificationCompat.PRIORITY_HIGH)
      .setAutoCancel(true)
    if (launch != null) {
      note.setContentIntent(
        PendingIntent.getActivity(
          this,
          0,
          launch,
          PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        ),
      )
    }
    manager.notify(70, note.build())
    result.success(true)
  }

  private fun needed(): Array<String> {
    val list =
      mutableListOf(
        Manifest.permission.ACCESS_COARSE_LOCATION,
        Manifest.permission.ACCESS_FINE_LOCATION,
        Manifest.permission.CAMERA,
        Manifest.permission.RECORD_AUDIO,
      )
    return list.toTypedArray()
  }

  private fun requestSetup(result: MethodChannel.Result) {
    val missing =
      needed().filter {
        ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
      }
    if (missing.isEmpty()) {
      result.success(mapOf("ok" to true))
      return
    }
    if (pending != null) {
      result.error("busy", "already requesting", null)
      return
    }
    pending = result
    ActivityCompat.requestPermissions(this, missing.toTypedArray(), reqCode)
  }

  override fun onRequestPermissionsResult(
    requestCode: Int,
    permissions: Array<out String>,
    grantResults: IntArray,
  ) {
    super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    if (requestCode != reqCode) return
    val result = pending ?: return
    pending = null
    val granted =
      permissions
        .zip(grantResults.toList())
        .associate { (permission, grant) ->
          permission to (grant == PackageManager.PERMISSION_GRANTED)
        }
    result.success(mapOf("ok" to true, "granted" to granted))
  }
}
