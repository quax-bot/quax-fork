package com.teskann.quax

import android.app.ActivityManager
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaCodecList
import android.media.MediaScannerConnection
import android.os.Build
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.webkit.MimeTypeMap
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.IOException

class MainActivity : FlutterActivity() {
    private val CHANNEL = "browser_resolver"
    private val sharedLinkRegex = Regex(
        "https?://(?:[\\w-]+\\.)*(?:x\\.com|twitter\\.com|t\\.co|fxtwitter\\.com|vxtwitter\\.com|fixupx\\.com)(?:[/?#]\\S*)?"
    )
    private val pickDownloadDirectoryRequest = 4111
    private var pendingDirectoryPick: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        intent = sharedLinkAsViewIntent(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(sharedLinkAsViewIntent(intent))
    }

    private fun sharedLinkAsViewIntent(intent: Intent): Intent {
        if (intent.action != Intent.ACTION_SEND) return intent
        val link = intent.getStringExtra(Intent.EXTRA_TEXT)
            ?.let { sharedLinkRegex.find(it)?.value }
            ?: return intent
        return Intent(Intent.ACTION_VIEW, android.net.Uri.parse(link))
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "scanMediaFile") {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        MediaScannerConnection.scanFile(context, arrayOf(path), null) { _, _ ->
                            result.success(null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "Path is null", null)
                    }
                } else if (call.method == "getDefaultBrowser") {
                    val intent = Intent(Intent.ACTION_VIEW).apply {
                        data = android.net.Uri.parse("https://")
                    }
                    val resolveInfo = packageManager.resolveActivity(
                        intent,
                        PackageManager.MATCH_DEFAULT_ONLY
                    )
                    if (resolveInfo != null) {
                        result.success(resolveInfo.activityInfo.packageName)
                    } else {
                        result.success(null)
                    }
                } else if (call.method == "enableWebViewPopups") {
                    WebViewPopups.install(this)
                    result.success(null)
                } else if (call.method == "pickDownloadDirectory") {
                    pickDownloadDirectory(result)
                } else if (call.method == "saveToDirectory") {
                    saveToDirectory(
                        call.argument<String>("directoryUri")!!,
                        call.argument<String>("fileName")!!,
                        call.argument<ByteArray>("data")!!,
                        result
                    )
                } else if (call.method == "getVideoHardware") {
                    val activityManager = getSystemService(ACTIVITY_SERVICE) as ActivityManager
                    result.success(mapOf(
                        "heapLimitMb" to activityManager.memoryClass,
                        "maxHardwareDecoders" to maxHardwareDecoders("video/avc"),
                    ))
                }
            }
    }

    private fun pickDownloadDirectory(result: MethodChannel.Result) {
        pendingDirectoryPick?.success(null)
        pendingDirectoryPick = result
        startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE), pickDownloadDirectoryRequest)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != pickDownloadDirectoryRequest) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val directory = data?.data?.takeIf { resultCode == RESULT_OK }
        directory?.let { keepOnlyPermissionOn(it) }
        pendingDirectoryPick?.success(directory?.toString())
        pendingDirectoryPick = null
    }

    private fun keepOnlyPermissionOn(directory: Uri) {
        val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        contentResolver.persistedUriPermissions
            .filter { it.uri != directory }
            .forEach { contentResolver.releasePersistableUriPermission(it.uri, flags) }
        contentResolver.takePersistableUriPermission(directory, flags)
    }

    private fun saveToDirectory(directoryUri: String, fileName: String, data: ByteArray, result: MethodChannel.Result) {
        val mainThread = Handler(Looper.getMainLooper())
        Thread {
            try {
                writeDocument(Uri.parse(directoryUri), fileName, data)
                mainThread.post { result.success(null) }
            } catch (e: Exception) {
                mainThread.post { result.error("save_failed", e.toString(), null) }
            }
        }.start()
    }

    private fun writeDocument(tree: Uri, fileName: String, data: ByteArray) {
        val directory = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        val mimeType = MimeTypeMap.getSingleton()
            .getMimeTypeFromExtension(fileName.substringAfterLast('.', "").lowercase())
            ?: "application/octet-stream"
        val document = DocumentsContract.createDocument(contentResolver, directory, mimeType, fileName)
            ?: throw IOException("Cannot create $fileName in $tree")
        contentResolver.openOutputStream(document)?.use { it.write(data) }
            ?: throw IOException("Cannot write $document")
    }

    private fun maxHardwareDecoders(mime: String): Int =
        MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos
            .filter { !it.isEncoder && it.supportedTypes.any { type -> type.equals(mime, ignoreCase = true) } }
            .filter { Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || it.isHardwareAccelerated }
            .maxOfOrNull { it.getCapabilitiesForType(mime).maxSupportedInstances } ?: 0
}
