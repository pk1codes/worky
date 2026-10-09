package com.pk1codes.worky

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
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
  }

  private fun needed(): Array<String> {
    val list =
      mutableListOf(
        Manifest.permission.ACCESS_COARSE_LOCATION,
        Manifest.permission.ACCESS_FINE_LOCATION,
        Manifest.permission.CAMERA,
        Manifest.permission.RECORD_AUDIO,
      )
    if (Build.VERSION.SDK_INT >= 33) {
      list.add(Manifest.permission.READ_MEDIA_IMAGES)
      list.add(Manifest.permission.READ_MEDIA_VIDEO)
      list.add(Manifest.permission.READ_MEDIA_AUDIO)
    } else {
      list.add(Manifest.permission.READ_EXTERNAL_STORAGE)
    }
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
