package com.example.tmr_tau

import android.content.pm.PackageManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "tmr_tau/maps_config"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isConfigured" -> result.success(isMapsApiKeyConfigured())
                    else -> result.notImplemented()
                }
            }
    }

    private fun isMapsApiKeyConfigured(): Boolean {
        return try {
            val appInfo = packageManager.getApplicationInfo(
                packageName,
                PackageManager.GET_META_DATA
            )
            val key = appInfo.metaData?.getString("com.google.android.geo.API_KEY")?.trim()
            !key.isNullOrEmpty()
        } catch (_: Exception) {
            false
        }
    }
}
