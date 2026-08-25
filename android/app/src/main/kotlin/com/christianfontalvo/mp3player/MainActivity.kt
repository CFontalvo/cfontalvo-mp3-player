package com.christianfontalvo.mp3player

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.ryanheise.audioservice.AudioServiceActivity
import java.util.ArrayDeque
import java.util.Locale
import java.util.concurrent.Executors

class MainActivity : AudioServiceActivity() {
    private val mediaExecutor = Executors.newSingleThreadExecutor()
    private var pendingFolderResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MEDIA_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getSelectedFolder" -> result.success(getSelectedFolder())
                "chooseFolder" -> chooseFolder(result)
                "querySongs" -> querySongsAsync(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun chooseFolder(result: MethodChannel.Result) {
        if (pendingFolderResult != null) {
            result.error("FOLDER_PICKER_ACTIVE", "El selector ya está abierto.", null)
            return
        }

        pendingFolderResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PREFIX_URI_PERMISSION,
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                getSelectedTreeUri()?.let {
                    putExtra(DocumentsContract.EXTRA_INITIAL_URI, it)
                }
            }
        }
        startActivityForResult(intent, FOLDER_REQUEST_CODE)
    }

    @Deprecated("Deprecated in Android, but required by FlutterActivity compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != FOLDER_REQUEST_CODE) return

        val result = pendingFolderResult ?: return
        pendingFolderResult = null
        val treeUri = data?.data
        if (resultCode != Activity.RESULT_OK || treeUri == null) {
            result.success(null)
            return
        }

        try {
            contentResolver.takePersistableUriPermission(
                treeUri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
            val folderName = queryDisplayName(
                DocumentsContract.buildDocumentUriUsingTree(
                    treeUri,
                    DocumentsContract.getTreeDocumentId(treeUri),
                ),
            ) ?: "Carpeta seleccionada"
            saveSelectedFolder(treeUri, folderName)
            result.success(folderInfo(treeUri, folderName))
        } catch (error: Exception) {
            result.error("FOLDER_PERMISSION_FAILED", error.message, null)
        }
    }

    private fun querySongsAsync(result: MethodChannel.Result) {
        val treeUri = getSelectedTreeUri()
        if (treeUri == null) {
            result.success(emptyList<Map<String, Any?>>())
            return
        }

        mediaExecutor.execute {
            try {
                val songs = querySongs(treeUri)
                runOnUiThread { result.success(songs) }
            } catch (error: SecurityException) {
                clearSelectedFolder()
                runOnUiThread {
                    result.error(
                        "FOLDER_ACCESS_LOST",
                        "Android retiró el acceso a la carpeta. Selecciónala de nuevo.",
                        null,
                    )
                }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error("FOLDER_QUERY_FAILED", error.message, null)
                }
            }
        }
    }

    private fun querySongs(treeUri: Uri): List<Map<String, Any?>> {
        val rootDocumentId = DocumentsContract.getTreeDocumentId(treeUri)
        val pendingFolders = ArrayDeque<Pair<String, String>>()
        val visitedFolders = mutableSetOf<String>()
        val songs = mutableListOf<Map<String, Any?>>()
        pendingFolders.add(rootDocumentId to "")

        while (pendingFolders.isNotEmpty()) {
            val (folderDocumentId, relativeFolder) = pendingFolders.removeFirst()
            if (!visitedFolders.add(folderDocumentId)) continue

            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
                treeUri,
                folderDocumentId,
            )
            contentResolver.query(
                childrenUri,
                arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_MIME_TYPE,
                ),
                null,
                null,
                null,
            )?.use { cursor ->
                val idColumn = cursor.getColumnIndexOrThrow(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                )
                val nameColumn = cursor.getColumnIndexOrThrow(
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                )
                val mimeColumn = cursor.getColumnIndexOrThrow(
                    DocumentsContract.Document.COLUMN_MIME_TYPE,
                )

                while (cursor.moveToNext()) {
                    val documentId = cursor.getString(idColumn)
                    val displayName = cursor.getString(nameColumn) ?: "Audio"
                    val mimeType = cursor.getString(mimeColumn)
                    if (mimeType == DocumentsContract.Document.MIME_TYPE_DIR) {
                        val childPath = if (relativeFolder.isEmpty()) {
                            displayName
                        } else {
                            "$relativeFolder/$displayName"
                        }
                        pendingFolders.add(documentId to childPath)
                    } else if (isAudioFile(mimeType, displayName)) {
                        val documentUri = DocumentsContract.buildDocumentUriUsingTree(
                            treeUri,
                            documentId,
                        )
                        songs.add(
                            mapOf(
                                "id" to documentUri.toString(),
                                "displayName" to displayName,
                                "title" to displayName.substringBeforeLast('.'),
                                "artist" to null,
                                "folder" to relativeFolder.takeIf { it.isNotEmpty() },
                                "uri" to documentUri.toString(),
                            ),
                        )
                    }
                }
            }
        }

        return songs.sortedBy { (it["title"] as String).lowercase(Locale.getDefault()) }
    }

    private fun isAudioFile(mimeType: String?, displayName: String): Boolean {
        val extension = displayName.substringAfterLast('.', "").lowercase(Locale.ROOT)
        return if (extension.isNotEmpty()) {
            extension in AUDIO_EXTENSIONS
        } else {
            mimeType?.startsWith("audio/") == true
        }
    }

    private fun getSelectedFolder(): Map<String, String>? {
        val treeUri = getSelectedTreeUri() ?: return null
        val storedName = preferences().getString(PREF_FOLDER_NAME, null)
        val name = storedName ?: queryDisplayName(
            DocumentsContract.buildDocumentUriUsingTree(
                treeUri,
                DocumentsContract.getTreeDocumentId(treeUri),
            ),
        ) ?: "Carpeta seleccionada"
        return folderInfo(treeUri, name)
    }

    private fun folderInfo(treeUri: Uri, name: String) = mapOf(
        "uri" to treeUri.toString(),
        "name" to name,
    )

    private fun queryDisplayName(documentUri: Uri): String? = contentResolver.query(
        documentUri,
        arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
        null,
        null,
        null,
    )?.use { cursor ->
        if (cursor.moveToFirst()) cursor.getString(0) else null
    }

    private fun saveSelectedFolder(treeUri: Uri, name: String) {
        preferences().edit()
            .putString(PREF_TREE_URI, treeUri.toString())
            .putString(PREF_FOLDER_NAME, name)
            .apply()
    }

    private fun clearSelectedFolder() {
        preferences().edit()
            .remove(PREF_TREE_URI)
            .remove(PREF_FOLDER_NAME)
            .apply()
    }

    private fun getSelectedTreeUri(): Uri? = preferences()
        .getString(PREF_TREE_URI, null)
        ?.let(Uri::parse)

    private fun preferences() = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)

    override fun onDestroy() {
        pendingFolderResult?.error("ACTIVITY_DESTROYED", "La actividad se cerró.", null)
        pendingFolderResult = null
        mediaExecutor.shutdown()
        super.onDestroy()
    }

    companion object {
        private const val MEDIA_CHANNEL = "com.christianfontalvo.mp3player/media"
        private const val FOLDER_REQUEST_CODE = 7001
        private const val PREFS_NAME = "music_library"
        private const val PREF_TREE_URI = "selected_tree_uri"
        private const val PREF_FOLDER_NAME = "selected_folder_name"
        private val AUDIO_EXTENSIONS = setOf(
            "mp3",
            "m4a",
            "aac",
            "flac",
            "wav",
            "ogg",
            "opus",
            "amr",
        )
    }
}
