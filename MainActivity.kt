package ae.wealthbuddy.wealth_buddy

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private var pending: MethodChannel.Result? = null
    private var toSave: ByteArray? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "wealthbuddy/files").setMethodCallHandler { call, result ->
            if (pending != null) {
                result.error("busy", "A file dialog is already open", null)
                return@setMethodCallHandler
            }
            when (call.method) {
                "save" -> {
                    toSave = call.argument<ByteArray>("bytes")
                    pending = result
                    val intent = Intent(Intent.ACTION_CREATE_DOCUMENT)
                        .addCategory(Intent.CATEGORY_OPENABLE)
                        .setType("application/octet-stream")
                        .putExtra(Intent.EXTRA_TITLE, call.argument<String>("name"))
                    startActivityForResult(intent, SAVE)
                }
                "open" -> {
                    pending = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
                        .addCategory(Intent.CATEGORY_OPENABLE)
                        .setType("*/*")
                    startActivityForResult(intent, OPEN)
                }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != SAVE && requestCode != OPEN) return
        val result = pending ?: return
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            toSave = null
            result.success(null)
            return
        }
        try {
            if (requestCode == SAVE) {
                contentResolver.openOutputStream(uri, "wt")?.use { it.write(toSave ?: ByteArray(0)) }
                toSave = null
                result.success(true)
            } else {
                val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                result.success(bytes)
            }
        } catch (e: Exception) {
            result.error("io", e.message, null)
        }
    }

    companion object {
        private const val SAVE = 4711
        private const val OPEN = 4712
    }
}
