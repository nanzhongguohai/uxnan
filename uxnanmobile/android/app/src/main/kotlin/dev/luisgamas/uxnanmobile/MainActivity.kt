package dev.luisgamas.uxnanmobile

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val installerChannel = "dev.luisgamas.uxnanmobile/installer"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, installerChannel).setMethodCallHandler { call, result ->
            if (call.method == "installApk") {
                val filePath = call.argument<String>("filePath")
                if (filePath == null) {
                    result.error("INVALID_ARGUMENT", "filePath is required", null)
                    return@setMethodCallHandler
                }
                val file = File(filePath)
                if (!file.exists()) {
                    result.error("FILE_NOT_FOUND", "File does not exist: $filePath", null)
                    return@setMethodCallHandler
                }

                try {
                    val context = applicationContext
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        if (!context.packageManager.canRequestPackageInstalls()) {
                            val manageIntent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                                data = Uri.parse("package:${context.packageName}")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(manageIntent)
                            result.error("PERMISSION_REQUIRED", "Unknown sources permission required. Please allow and retry.", null)
                            return@setMethodCallHandler
                        }
                    }

                    val apkUri = FileProvider.getUriForFile(
                        context,
                        "${context.packageName}.fileprovider",
                        file
                    )
                    val installIntent = Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(apkUri, "application/vnd.android.package-archive")
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(installIntent)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("INSTALL_FAILED", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}