package com.example.stut_food_intake_project

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 前景服務(lib/services/foreground_keep_alive_service.dart)啟動前要先確認有
        // 藍牙權限。這裡只檢查,不會跳出詢問視窗。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PERMISSION_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasBluetoothConnect" -> result.success(hasBluetoothConnect())
                    else -> result.notImplemented()
                }
            }
    }

    // Android 12(API 31)起才有 BLUETOOTH_CONNECT 這個執行期權限;更舊的版本不需要。
    private fun hasBluetoothConnect(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) ==
            PackageManager.PERMISSION_GRANTED

    private companion object {
        const val PERMISSION_CHANNEL = "smart_cup/permissions"
    }
}
