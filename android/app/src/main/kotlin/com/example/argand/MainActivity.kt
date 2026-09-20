package com.example.argand

import android.content.Intent
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

/**
 * Receives media shared into the app from the Android Sharesheet.
 *
 * Flutter cannot read a `content://` URI: it is not a filesystem path, and the
 * read grant behind it belongs to this Activity and is revocable. So the native
 * side owns two things Dart cannot do — resolving the URI's display name, and
 * copying its bytes out before the grant lapses.
 *
 * Deliberately split into two channel calls rather than one.
 *
 *  - [takeInitialShare] and the `share` callback carry only **metadata**, which
 *    is cheap and safe on the main thread.
 *  - [copySharedMedia] does the actual byte copy, on a background executor.
 *    A shared video routinely runs to hundreds of megabytes; copying that
 *    inline would block the main thread long enough to ANR.
 *
 * Sharing arrives two ways and both are handled: a cold start, where the intent
 * is already on the Activity by the time the engine is configured, and a warm
 * one, where `onNewIntent` fires on the running app. `singleTop` in the
 * manifest is what routes the second case here rather than starting a second
 * Activity.
 */
class MainActivity : FlutterActivity() {
    private companion object {
        const val CHANNEL = "argand/shared_media"

        /** Frame extraction for the timeline's filmstrip. See [extractFrames]. */
        const val THUMBNAIL_CHANNEL = "argand/thumbnails"

        /** Where copies land. Cleared by the OS under storage pressure, and by
         *  Dart as soon as the import has adopted the file. */
        const val CACHE_DIR = "shared"

        /** Filmstrip frames are rendered a few dozen pixels wide, so anything
         *  larger is decoded and scaled for nothing. */
        const val THUMBNAIL_WIDTH = 160

        const val THUMBNAIL_QUALITY = 70
    }

    private var channel: MethodChannel? = null
    private var thumbnails: MethodChannel? = null

    /**
     * Video export, which owns its own channel rather than adding methods
     * here: it is unrelated to sharing and has a run that outlives a call.
     */
    private val videoExport = VideoExportChannel(this)

    /** A share that arrived before Dart was listening, handed over on request. */
    private var pending: Map<String, String>? = null

    private val io = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .also { it.setMethodCallHandler(::onMethodCall) }

        thumbnails = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, THUMBNAIL_CHANNEL)
            .also { it.setMethodCallHandler(::onThumbnailCall) }

        videoExport.attach(flutterEngine.dartExecutor.binaryMessenger)

        // Read at configure time rather than in onCreate: a cold start launched
        // by a share has the intent waiting, and Dart asks for it once it is
        // ready rather than racing to be listening first.
        pending = describe(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)

        val share = describe(intent) ?: return
        val sink = channel
        if (sink == null) {
            pending = share
            return
        }
        sink.invokeMethod("share", share)
    }

    override fun onDestroy() {
        videoExport.detach()
        io.shutdown()
        super.onDestroy()
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "takeInitialShare" -> {
                // Taken, not read: a share must launch exactly one import, and
                // leaving it in place would re-import on every hot restart.
                result.success(pending)
                pending = null
            }

            "copySharedMedia" -> {
                val uri = call.argument<String>("uri")
                val name = call.argument<String>("name") ?: "shared"
                if (uri == null) {
                    result.error("no_uri", "copySharedMedia needs a uri", null)
                    return
                }
                copyAsync(Uri.parse(uri), name, result)
            }

            else -> result.notImplemented()
        }
    }

    /** Metadata only — no bytes are read here. */
    private fun describe(intent: Intent?): Map<String, String>? {
        if (intent == null) return null
        if (intent.action != Intent.ACTION_SEND) return null

        val type = intent.type ?: return null
        // Anything else the Sharesheet offered us is not something this app can
        // transcribe. The manifest already filters, but an intent can be built
        // by hand and this is the app's own check.
        if (!type.startsWith("video/") && !type.startsWith("audio/")) return null

        val uri = streamExtra(intent) ?: return null
        return mapOf("uri" to uri.toString(), "name" to displayName(uri))
    }

    @Suppress("DEPRECATION")
    private fun streamExtra(intent: Intent): Uri? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }
    }

    /**
     * The name the sharing app gave the file.
     *
     * Falls back to the URI's last path segment, and then to a constant: the
     * name is only used for the project title and the file extension, so an
     * imperfect one is far better than refusing the import.
     */
    private fun displayName(uri: Uri): String {
        try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    val column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (column >= 0 && cursor.moveToFirst()) {
                        val name = cursor.getString(column)
                        if (!name.isNullOrBlank()) return name
                    }
                }
        } catch (_: Exception) {
            // A provider that refuses to be queried still hands over bytes.
        }
        return uri.lastPathSegment?.takeIf { it.isNotBlank() } ?: "shared"
    }

    private fun onThumbnailCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "extractFrames") {
            result.notImplemented()
            return
        }

        val mediaPath = call.argument<String>("mediaPath")
        val outputDir = call.argument<String>("outputDir")
        val count = call.argument<Int>("count") ?: 0
        if (mediaPath == null || outputDir == null || count <= 0) {
            result.error("bad_args", "extractFrames needs mediaPath, outputDir and count", null)
            return
        }

        extractFramesAsync(mediaPath, outputDir, count, result)
    }

    /**
     * Samples [count] frames evenly across a media file and writes them as JPEGs.
     *
     * Uses [MediaMetadataRetriever], the platform's own decoder — the same
     * no-FFmpeg rule the audio pipeline follows (docs/engine-architecture.md).
     *
     * `getFrameAtTime` rather than `getScaledFrameAtTime`, which would hand back
     * an already-downscaled bitmap but needs API 27; scaling here instead keeps
     * the app's `minSdk` free to stay where Flutter puts it.
     *
     * Runs on the same background executor the share-sheet copy uses. Decoding
     * a dozen frames out of a long video is far too slow for the main thread,
     * and an audio-only file simply yields nothing rather than failing — a clip
     * with no video track has no frames to show, which is not an error.
     */
    private fun extractFramesAsync(
        mediaPath: String,
        outputDir: String,
        count: Int,
        result: MethodChannel.Result,
    ) {
        io.execute {
            val outcome = runCatching {
                val dir = File(outputDir).apply { mkdirs() }
                val retriever = MediaMetadataRetriever()
                val paths = mutableListOf<String>()

                try {
                    retriever.setDataSource(mediaPath)
                    val durationMs = retriever
                        .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                        ?.toLongOrNull() ?: 0L

                    for (index in 0 until count) {
                        // Sampled at the midpoint of each slice rather than its
                        // edge: the first frame of a video is often a black or
                        // faded-in frame, which would make the strip open on
                        // nothing.
                        val atMs = if (durationMs <= 0) 0L
                        else durationMs * (2 * index + 1) / (2 * count)

                        val frame = retriever.getFrameAtTime(
                            atMs * 1000,
                            MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                        ) ?: continue

                        val height = (frame.height * THUMBNAIL_WIDTH / frame.width.toFloat()).toInt()
                        val scaled = Bitmap.createScaledBitmap(
                            frame,
                            THUMBNAIL_WIDTH,
                            height.coerceAtLeast(1),
                            true,
                        )

                        val file = File(dir, "$index.jpg")
                        FileOutputStream(file).use {
                            scaled.compress(Bitmap.CompressFormat.JPEG, THUMBNAIL_QUALITY, it)
                        }
                        if (scaled != frame) scaled.recycle()
                        frame.recycle()

                        paths.add(file.absolutePath)
                    }
                } finally {
                    retriever.release()
                }

                paths
            }

            runOnUiThread {
                outcome.fold(
                    onSuccess = result::success,
                    onFailure = { result.error("frames_failed", it.message, null) },
                )
            }
        }
    }

    private fun copyAsync(uri: Uri, name: String, result: MethodChannel.Result) {
        io.execute {
            val outcome = runCatching {
                val dir = File(cacheDir, CACHE_DIR).apply { mkdirs() }
                // Prefixed so two shares of the same filename cannot collide
                // while the first is still importing.
                val destination = File(dir, "${System.nanoTime()}-${name.takeLast(80)}")

                contentResolver.openInputStream(uri).use { input ->
                    requireNotNull(input) { "No stream for $uri" }
                    destination.outputStream().use { input.copyTo(it) }
                }
                destination.absolutePath
            }

            runOnUiThread {
                outcome.fold(
                    onSuccess = result::success,
                    onFailure = { result.error("copy_failed", it.message, null) },
                )
            }
        }
    }
}
