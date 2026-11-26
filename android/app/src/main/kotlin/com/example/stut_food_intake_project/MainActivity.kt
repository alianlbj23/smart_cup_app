package com.example.stut_food_intake_project

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // App 自動更新:Dart 端(lib/services/update_installer.dart)下載好 APK 後,
        // 由這裡開啟系統的安裝程式。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATE_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "installApk") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("BAD_ARGUMENT", "path is required", null)
                    return@setMethodCallHandler
                }
                installApk(path, result)
            }
    }

    private fun installApk(path: String, result: MethodChannel.Result) {
        try {
            // 只接受快取資料夾底下 smart_cup_update/ 裡的 APK
            // (和 res/xml/update_file_paths.xml 開放的範圍一致)。
            val dir = File(cacheDir, UPDATE_DIR).canonicalFile
            val apk = File(path).canonicalFile
            if (apk.parentFile != dir || apk.extension != "apk" || !apk.isFile) {
                result.error("BAD_ARGUMENT", "not a downloaded update", null)
                return
            }
            // Android 8 起要使用者先允許這個 App「安裝未知應用程式」。
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                !packageManager.canRequestPackageInstalls()
            ) {
                startActivity(
                    Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:$packageName"),
                    ),
                )
                result.error("NEEDS_PERMISSION", "install permission not granted", null)
                return
            }
            val uri = FileProvider.getUriForFile(this, "$packageName.update_provider", apk)
            startActivity(
                Intent(Intent.ACTION_VIEW)
                    .setDataAndType(uri, "application/vnd.android.package-archive")
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            result.success(null)
        } catch (e: ActivityNotFoundException) {
            Log.e(TAG, "no activity to install the update", e)
            result.error("INSTALL_FAILED", "no installer available", null)
        } catch (e: IOException) {
            Log.e(TAG, "cannot resolve the update file", e)
            result.error("INSTALL_FAILED", "cannot read the update file", null)
        } catch (e: IllegalArgumentException) {
            // FileProvider 不認得這個路徑。
            Log.e(TAG, "update file is outside the shared folder", e)
            result.error("INSTALL_FAILED", "cannot share the update file", null)
        } catch (e: SecurityException) {
            Log.e(TAG, "not allowed to start the installer", e)
            result.error("INSTALL_FAILED", "not allowed to start the installer", null)
        }
    }

    private companion object {
        const val TAG = "SmartCupUpdate"
        const val UPDATE_CHANNEL = "smart_cup/update"
        const val UPDATE_DIR = "smart_cup_update"
    }
}
