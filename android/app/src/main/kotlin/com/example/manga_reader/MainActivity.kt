package com.example.manga_reader

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.manga_reader/external_file"
    private var methodChannel: MethodChannel? = null
    private var pendingFileData: Map<String, Any>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingFileData = handleIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialFile" -> {
                    val data = pendingFileData
                    pendingFileData = null
                    result.success(data)
                }
                "clearInitialFile" -> {
                    pendingFileData = null
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val fileData = handleIntent(intent)
        if (fileData != null) {
            pendingFileData = fileData
            methodChannel?.invokeMethod("onFileOpened", fileData)
        }
    }

    private fun handleIntent(intent: Intent?): Map<String, Any>? {
        if (intent == null) return null
        val action = intent.action
        if (action != Intent.ACTION_VIEW && action != Intent.ACTION_SEND) return null

        val uri: Uri? = if (action == Intent.ACTION_SEND) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        } else {
            intent.data
        }

        if (uri == null) return null

        return try {
            val fileName = getFileName(uri) ?: "imported_file"
            val ext = getFileExtension(fileName)
            val supportedExts = listOf("cbz", "cbr", "zip", "epub", "pdf")
            
            // Only accept supported file extensions or fallback if mimeType matches
            val mimeType = intent.type ?: contentResolver.getType(uri) ?: ""
            val isSupported = supportedExts.contains(ext.lowercase()) ||
                    mimeType.contains("epub") ||
                    mimeType.contains("pdf") ||
                    mimeType.contains("zip") ||
                    mimeType.contains("cbz") ||
                    mimeType.contains("cbr")

            if (!isSupported) return null

            val targetFile = copyUriToCache(uri, fileName) ?: return null
            
            mapOf(
                "filePath" to targetFile.absolutePath,
                "fileName" to fileName,
                "fileType" to (if (ext.isNotEmpty()) ext.lowercase() else "epub"),
                "fileSize" to targetFile.length()
            )
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    private fun getFileName(uri: Uri): String? {
        var name: String? = null
        if (uri.scheme == "content") {
            val cursor = contentResolver.query(uri, null, null, null, null)
            cursor?.use {
                if (it.moveToFirst()) {
                    val index = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index >= 0) {
                        name = it.getString(index)
                    }
                }
            }
        }
        if (name == null) {
            name = uri.path?.let { File(it).name }
        }
        return name
    }

    private fun getFileExtension(fileName: String): String {
        val lastDot = fileName.lastIndexOf('.')
        return if (lastDot >= 0 && lastDot < fileName.length - 1) {
            fileName.substring(lastDot + 1)
        } else {
            ""
        }
    }

    private fun copyUriToCache(uri: Uri, fileName: String): File? {
        return try {
            val cacheDir = File(cacheDir, "external_imports")
            if (!cacheDir.exists()) cacheDir.mkdirs()

            // Unique filename to prevent collision
            val safeName = "${System.currentTimeMillis()}_$fileName"
            val outputFile = File(cacheDir, safeName)

            val inputStream: InputStream? = contentResolver.openInputStream(uri)
            val outputStream = FileOutputStream(outputFile)

            inputStream?.use { input ->
                outputStream.use { output ->
                    input.copyTo(output)
                }
            }
            outputFile
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }
}
