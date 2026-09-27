package com.qprintsolutions.qprint

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.core.content.FileProvider
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "com.qprintsolutions.qprint/share_intent"
    private var initialSharedFiles: List<String>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        handleShareIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleShareIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialSharedFiles" -> {
                    val files = initialSharedFiles
                    initialSharedFiles = null
                    result.success(files)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun handleShareIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        val type = intent.type ?: return

        if (Intent.ACTION_SEND == action && type.startsWith("application/pdf") || type.startsWith("image/")) {
            val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            uri?.let {
                initialSharedFiles = listOf(copyToCacheIfNeeded(it))
            }
        } else if (Intent.ACTION_SEND_MULTIPLE == action && type.startsWith("application/pdf") || type.startsWith("image/")) {
            val uris = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
            if (!uris.isNullOrEmpty()) {
                initialSharedFiles = uris.map { copyToCacheIfNeeded(it) }
            }
        }
    }

    private fun copyToCacheIfNeeded(uri: Uri): String {
        if ("file".equals(uri.scheme, ignoreCase = true)) {
            return uri.path ?: ""
        }

        return try {
            val cacheDir = cacheDir
            val rawName = uri.lastPathSegment?.substringAfterLast('/') ?: "shared_document"
            val baseName = if (rawName.isBlank()) "shared_document" else rawName

            // Infer a sensible extension from MIME type so backend can
            // reliably detect PDFs vs images when calculating cost.
            val mime = contentResolver.getType(uri) ?: ""
            val inferredExt = when {
                mime == "application/pdf" -> ".pdf"
                mime == "image/png" -> ".png"
                mime == "image/jpeg" || mime == "image/jpg" -> ".jpg"
                mime.startsWith("image/") -> ".jpg"
                else -> ""
            }

            val fileName = if (inferredExt.isNotEmpty() && !baseName.lowercase().endsWith(inferredExt)) {
                "$baseName$inferredExt"
            } else {
                baseName
            }

            val dest = File(cacheDir, fileName)
            contentResolver.openInputStream(uri)?.use { input ->
                dest.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
            dest.absolutePath
        } catch (e: Exception) {
            ""
        }
    }
}

