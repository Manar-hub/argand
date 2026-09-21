package com.example.argand

import android.app.Activity
import android.content.ContentValues
import android.media.MediaCodecInfo
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.text.SpannableString
import android.text.Spanned
import android.text.style.AbsoluteSizeSpan
import android.text.style.BackgroundColorSpan
import android.text.style.ForegroundColorSpan
import androidx.media3.common.C
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.common.OverlaySettings
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.Presentation
import androidx.media3.effect.StaticOverlaySettings
import androidx.media3.effect.TextOverlay
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.concurrent.Executors
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Renders a project's clips into a single MP4 and publishes it to Downloads.
 *
 * Kept out of [MainActivity] deliberately. That class is about receiving share
 * intents and has a lifetime tied to `onNewIntent`; export is unrelated work
 * that happens to need the same engine.
 *
 * **Runs on the main thread, unlike the copy and thumbnail work next door.**
 * That looks wrong beside [MainActivity]'s background executor, and is not.
 * `Transformer` must be built and started on a thread with a `Looper`, because
 * it delivers its callbacks there; it then does the actual decode and encode on
 * its own internal threads. Handing it to a bare executor throws. So the main
 * thread here holds only the bookkeeping, never the encoding.
 *
 * **The render goes to a cache file first and is published afterwards.** Two
 * reasons: from API 29 a MediaStore entry has no filesystem path and
 * `Transformer.start` takes a path, and publishing only on success keeps a
 * failed or cancelled render out of the user's Downloads folder entirely.
 *
 * Progress is **polled, not pushed**: Transformer exposes
 * `getProgress(ProgressHolder)` and has no progress callback, so a handler
 * samples it a few times a second and forwards each reading to Dart.
 */
@UnstableApi
class VideoExportChannel(private val activity: Activity) : MethodChannel.MethodCallHandler {

    private companion object {
        const val CHANNEL = "argand/video_export"

        /** Four samples a second: fast enough to look live, cheap enough to ignore. */
        const val PROGRESS_INTERVAL_MS = 250L

        const val MIME_TYPE = "video/mp4"

        /**
         * Fallback output size when a clip reports no dimensions at all.
         * 720p rather than 1080p: an unreadable file is a failure either way,
         * and the smaller guess is the one the emulator can actually encode.
         */
        const val FALLBACK_WIDTH = 1280
        const val FALLBACK_HEIGHT = 720

        /**
         * Caption text height as a fraction of the output's short edge.
         *
         * Relative rather than absolute so captions read the same on a 720p
         * export and a 4K one; a fixed pixel size is either unreadable on the
         * large frame or covers the small one.
         */
        const val CAPTION_TEXT_FRACTION = 0.045f

        /** Matches the preview's caption plate: black at 62%. */
        const val CAPTION_BACKGROUND = 0x9E000000.toInt()

        /**
         * How far up from the bottom the caption sits, in normalised device
         * coordinates where -1 is the bottom edge and 1 the top.
         */
        const val CAPTION_ANCHOR_Y = -0.82f
    }

    /**
     * Draws a clip's captions over it, one cue at a time.
     *
     * **Time here is the item's own, not the project's.** Media3 gives each
     * item in a sequence a presentation timebase starting at zero, and word
     * timings are already stored clip-relative, so the two agree with no
     * conversion -- which is the reason captions attach per item rather than
     * once over the whole composition.
     */
    private class CaptionOverlay(
        private val captions: List<Caption>,
        private val textSizePx: Int,
    ) : TextOverlay() {

        private val settings = StaticOverlaySettings.Builder()
            .setBackgroundFrameAnchor(0f, CAPTION_ANCHOR_Y)
            .build()

        private val hidden = StaticOverlaySettings.Builder()
            .setBackgroundFrameAnchor(0f, CAPTION_ANCHOR_Y)
            .setAlphaScale(0f)
            .build()

        private fun activeAt(presentationTimeUs: Long): Caption? {
            val ms = presentationTimeUs / 1000
            // Half-open, matching every other interval in this project: a cue
            // ending exactly where the next begins must not render both.
            return captions.firstOrNull { ms >= it.startMs && ms < it.endMs }
        }

        override fun getText(presentationTimeUs: Long): SpannableString {
            val caption = activeAt(presentationTimeUs)
                // **A space, not an empty string.** The base class renders
                // whatever comes back into a bitmap, and an empty string asks
                // for one of zero size. The gap is made invisible by alpha in
                // [getOverlaySettings] instead.
                ?: return SpannableString(" ")

            return SpannableString(caption.text).apply {
                setSpan(
                    ForegroundColorSpan(caption.colorArgb),
                    0,
                    length,
                    Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
                )
                setSpan(
                    BackgroundColorSpan(CAPTION_BACKGROUND),
                    0,
                    length,
                    Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
                )
                setSpan(
                    AbsoluteSizeSpan(textSizePx),
                    0,
                    length,
                    Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
                )
            }
        }

        override fun getOverlaySettings(presentationTimeUs: Long): OverlaySettings =
            if (activeAt(presentationTimeUs) == null) hidden else settings
    }

    /** One caption, in the clip's own timebase. */
    private data class Caption(
        val startMs: Long,
        val endMs: Long,
        val text: String,
        val colorArgb: Int,
    )

    private var channel: MethodChannel? = null
    private var transformer: Transformer? = null
    private var pending: MethodChannel.Result? = null

    /** The cache file currently being rendered into, deleted once published. */
    private var scratch: File? = null

    private val main = Handler(Looper.getMainLooper())

    /** Publishing copies the whole file, which must not touch the main thread. */
    private val io = Executors.newSingleThreadExecutor()

    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL).also { it.setMethodCallHandler(this) }
    }

    fun detach() {
        cancelRunning()
        io.shutdown()
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "export" -> {
                val clips = call.argument<List<Map<String, Any?>>>("clips")
                val fileName = call.argument<String>("fileName")
                if (clips.isNullOrEmpty() || fileName.isNullOrBlank()) {
                    result.error("bad_args", "export needs clips and fileName", null)
                    return
                }
                startExport(clips, fileName, result)
            }

            "cancel" -> {
                cancelRunning()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun startExport(
        clips: List<Map<String, Any?>>,
        fileName: String,
        result: MethodChannel.Result,
    ) {
        val clipPaths = clips.mapNotNull { it["path"] as? String }
        if (clipPaths.size != clips.size) {
            result.error("bad_args", "every clip needs a path", null)
            return
        }

        if (transformer != null) {
            // One export at a time. A second encode competes for the same
            // hardware codec and makes both slower than running them in order,
            // which is the reasoning the transcription runs already use.
            result.error("busy", "An export is already running", null)
            return
        }

        val missing = clipPaths.firstOrNull { !File(it).exists() }
        if (missing != null) {
            result.error("missing_clip", "Clip no longer exists: " + missing, null)
            return
        }

        // Every item is normalised to one size, taken from the first clip.
        // **A sequence of differently-sized items is the failure case here.**
        // Without this the encoder either rejects the mix or stretches later
        // clips to match the first, and a stretched export reads as a bug in
        // the editor rather than in the render.
        val size = outputSizeOf(clipPaths.first())
        val presentation: Effect = Presentation.createForWidthAndHeight(
            size.first,
            size.second,
            Presentation.LAYOUT_SCALE_TO_FIT,
        )
        // Sized against the short edge of the *output*, so the caption reads
        // the same whatever the source was.
        val textSizePx =
            (min(size.first, size.second) * CAPTION_TEXT_FRACTION).roundToInt()

        val items = clips.map { clip ->
            val path = clip["path"] as String
            val captions = captionsOf(clip["captions"])

            // **Presentation first, then the overlay.** Effects run in order,
            // so putting the caption first would size it against the source
            // frame and then scale it with everything else.
            val videoEffects = mutableListOf<Effect>(presentation)
            if (captions.isNotEmpty()) {
                videoEffects.add(
                    OverlayEffect(listOf(CaptionOverlay(captions, textSizePx))),
                )
            }

            // **Trimming is a clipping configuration, not a cut file.** The
            // media is shared between clips and between projects, so the
            // render reads a window of it rather than anything on disk being
            // altered. An absent or zero end means "to the end of the file".
            val start = (clip["startMs"] as? Number)?.toLong() ?: 0L
            val end = (clip["endMs"] as? Number)?.toLong() ?: 0L
            val clipping = MediaItem.ClippingConfiguration.Builder()
                .setStartPositionMs(start)
                .apply { if (end > start) setEndPositionMs(end) }
                .build()

            val mediaItem = MediaItem.Builder()
                .setUri(File(path).toURI().toString())
                .setClippingConfiguration(clipping)
                .build()

            EditedMediaItem.Builder(mediaItem)
                .setEffects(Effects(emptyList(), videoEffects))
                .build()
        }

        // Both the list and vararg constructors are deprecated in Media3
        // 1.11. The surviving one takes the set of track types to *force* into
        // the sequence, and it rejects an empty set outright -- the constructor
        // opens with `checkState(!trackTypes.isEmpty())`, so "force nothing" is
        // not expressible here and the deprecated constructors are the only
        // way to ask for infer-from-the-items.
        //
        // Forcing both is the right answer anyway, and not merely the legal
        // one: it is what lets a sequence concatenate when the items disagree.
        // A clip with no audio gets a silent track rather than derailing the
        // join, and an audio-only clip -- which this app can hold, since a WAV
        // imports as media like anything else -- gets a blank video track
        // instead of failing a video export.
        val composition = Composition.Builder(
            EditedMediaItemSequence.Builder(
                setOf(C.TRACK_TYPE_AUDIO, C.TRACK_TYPE_VIDEO),
            ).addItems(items).build(),
        ).build()

        val temp = File(activity.cacheDir, "exports/$fileName")
        temp.parentFile?.mkdirs()
        temp.delete()
        scratch = temp

        pending = result
        transformer = Transformer.Builder(activity)
            .setEncoderFactory(encoderFactory(size))
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    publishAsync(temp, fileName, exportResult)
                }

                override fun onError(
                    composition: Composition,
                    exportResult: ExportResult,
                    exception: ExportException,
                ) {
                    temp.delete()
                    finish { it.error("export_failed", exception.message, null) }
                }
            })
            .build()

        transformer?.start(composition, temp.absolutePath)
        pollProgress()
    }

    /**
     * Moves the finished render into the user's Downloads folder.
     *
     * Off the main thread because it copies the whole file, which for a long
     * export is hundreds of megabytes.
     */
    private fun publishAsync(
        temp: File,
        fileName: String,
        exportResult: ExportResult,
    ) {
        io.execute {
            val outcome = runCatching {
                publish(temp, fileName) + describe(exportResult)
            }
            temp.delete()
            main.post {
                finish { result ->
                    outcome.fold(
                        onSuccess = result::success,
                        onFailure = {
                            result.error("publish_failed", it.message, null)
                        },
                    )
                }
            }
        }
    }

    /**
     * What the encoder says it produced.
     *
     * Reported so a caller can check the render against the timeline it asked
     * for. **Geometry is worth carrying even though it looks like trivia:** an
     * encoder that cannot take the requested portrait size may encode
     * landscape and set a rotation flag instead, which is correct but means
     * stored dimensions alone do not tell you the video is upright.
     */
    private fun describe(result: ExportResult): Map<String, Any?> = mapOf(
        // `durationMs` is deprecated in Media3 1.11; the surviving field
        // is explicit that the figure is approximate, which is why the
        // checks against it allow a tolerance rather than an exact match.
        "durationMs" to result.approximateDurationMs,
        "width" to result.width,
        "height" to result.height,
    )

    /**
     * Writes [temp] into the public Downloads collection.
     *
     * Returns what Dart needs to tell the user where it went, including the
     * **size as the store reports it back** rather than the size we wrote: that
     * is what proves the bytes actually landed rather than that a row was
     * created.
     */
    private fun publish(temp: File, fileName: String): Map<String, Any?> {
        if (!temp.exists() || temp.length() == 0L) {
            throw IOException("The render produced no file to publish")
        }

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            publishViaMediaStore(temp, fileName)
        } else {
            publishLegacy(temp, fileName)
        }
    }

    /**
     * API 29 and up. MediaStore owns Downloads and grants access per insert, so
     * no storage permission is involved.
     *
     * `IS_PENDING` hides the row until the bytes are in: without it a file
     * manager can show, and a user can open, a half-written video.
     */
    private fun publishViaMediaStore(temp: File, fileName: String): Map<String, Any?> {
        val resolver = activity.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, fileName)
            put(MediaStore.Downloads.MIME_TYPE, MIME_TYPE)
            put(MediaStore.Downloads.IS_PENDING, 1)
        }

        val uri: Uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IOException("Downloads rejected the new file")

        try {
            resolver.openOutputStream(uri)?.use { sink ->
                temp.inputStream().use { source -> source.copyTo(sink) }
            } ?: throw IOException("Could not open the published file for writing")

            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        } catch (error: Exception) {
            // Leaving a pending row behind would be an invisible file the user
            // can never see or delete.
            resolver.delete(uri, null, null)
            throw error
        }

        var name = fileName
        var bytes = 0L
        resolver.query(
            uri,
            arrayOf(MediaStore.Downloads.DISPLAY_NAME, MediaStore.Downloads.SIZE),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                // MediaStore de-duplicates names itself, so what it stored is
                // not necessarily what we asked for.
                name = cursor.getString(0) ?: fileName
                bytes = cursor.getLong(1)
            }
        }

        return mapOf(
            "name" to name,
            "uri" to uri.toString(),
            "sizeBytes" to bytes,
            "location" to "Download/$name",
        )
    }

    /**
     * API 28 and below, where Downloads is an ordinary directory and writing to
     * it needs `WRITE_EXTERNAL_STORAGE` (declared with `maxSdkVersion="28"`).
     *
     * **Not exercised by any test in this project** — the emulator runs API 37,
     * so only [publishViaMediaStore] is covered.
     */
    private fun publishLegacy(temp: File, fileName: String): Map<String, Any?> {
        @Suppress("DEPRECATION")
        val directory =
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        directory.mkdirs()

        // MediaStore uniquifies for us above; here it is ours to do, or a
        // second export silently overwrites the first.
        val stem = fileName.substringBeforeLast('.', fileName)
        val extension = fileName.substringAfterLast('.', "mp4")
        var target = File(directory, fileName)
        var attempt = 1
        while (target.exists()) {
            target = File(directory, "$stem ($attempt).$extension")
            attempt++
        }

        temp.inputStream().use { source ->
            target.outputStream().use { sink -> source.copyTo(sink) }
        }

        return mapOf(
            "name" to target.name,
            "uri" to Uri.fromFile(target).toString(),
            "sizeBytes" to target.length(),
            "location" to target.absolutePath,
        )
    }

    /**
     * Asks for a modern H.264 profile rather than taking what is offered.
     *
     * **The default was Constrained Baseline, and it is a bad deal.** Measured
     * on a 42-second clip, the export ran at 8.67 Mbps against the source's
     * 3.35 and still looked worse: Constrained Baseline has no CABAC and no
     * B-frames, so it spends far more bits for less picture. Asking for High
     * costs nothing and is where most of the quality went.
     *
     * The level is picked from the frame size because a level too low for the
     * resolution is rejected outright. Media3's fallback stays enabled, so a
     * device whose encoder cannot honour this request degrades to what it can
     * do instead of failing the export.
     */
    private fun encoderFactory(size: Pair<Int, Int>): DefaultEncoderFactory {
        val pixels = size.first.toLong() * size.second.toLong()
        val level = if (pixels > 1920L * 1080L) {
            MediaCodecInfo.CodecProfileLevel.AVCLevel51
        } else {
            MediaCodecInfo.CodecProfileLevel.AVCLevel41
        }

        val settings = VideoEncoderSettings.Builder()
            .setEncodingProfileLevel(
                MediaCodecInfo.CodecProfileLevel.AVCProfileHigh,
                level,
            )
            // Variable rate: a talking-head shot and a hand-held pan do not
            // deserve the same bits, and constant rate spends them evenly.
            .setBitrateMode(MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_VBR)
            .build()

        return DefaultEncoderFactory.Builder(activity)
            .setRequestedVideoEncoderSettings(settings)
            .build()
    }

    /**
     * Reads the caption list for one clip off the channel.
     *
     * **Numbers arrive as `Number`, not `Int`.** A colour like 0xFFFFD54F does
     * not fit in a signed 32-bit int, so Flutter's codec sends it as a long;
     * `toInt()` takes the low 32 bits back, which is the ARGB value again.
     * Reading it as `Int` directly would fail for every opaque colour.
     */
    private fun captionsOf(raw: Any?): List<Caption> {
        val list = raw as? List<*> ?: return emptyList()

        return list.mapNotNull { entry ->
            val map = entry as? Map<*, *> ?: return@mapNotNull null
            val text = map["text"] as? String ?: return@mapNotNull null
            if (text.isBlank()) return@mapNotNull null

            val start = (map["startMs"] as? Number)?.toLong() ?: return@mapNotNull null
            val end = (map["endMs"] as? Number)?.toLong() ?: return@mapNotNull null
            if (end <= start) return@mapNotNull null

            Caption(
                startMs = start,
                endMs = end,
                text = text,
                colorArgb = (map["colorArgb"] as? Number)?.toInt() ?: -1,
            )
        }
    }

    /**
     * Samples Transformer's progress and forwards each reading to Dart.
     *
     * Re-posts itself rather than running on a repeating timer, so it stops
     * naturally the moment the export is no longer running.
     */
    private fun pollProgress() {
        val running = transformer ?: return
        val holder = ProgressHolder()

        if (running.getProgress(holder) != Transformer.PROGRESS_STATE_NOT_STARTED) {
            channel?.invokeMethod("progress", holder.progress)
        }

        main.postDelayed({ pollProgress() }, PROGRESS_INTERVAL_MS)
    }

    private fun cancelRunning() {
        transformer?.cancel()
        scratch?.delete()
        finish { it.error("cancelled", "Export cancelled", null) }
    }

    /**
     * Resolves the outstanding call exactly once and clears the run.
     *
     * Transformer can report completion and then be cancelled by a teardown
     * arriving in the same frame, and replying twice to one
     * [MethodChannel.Result] throws. So the reference is taken and cleared
     * before it is used.
     */
    private fun finish(reply: (MethodChannel.Result) -> Unit) {
        main.removeCallbacksAndMessages(null)
        val result = pending
        pending = null
        transformer = null
        scratch = null
        if (result != null) reply(result)
    }

    /**
     * The pixel size to render at, read from the clip itself.
     *
     * Rotation matters: a phone video is commonly stored landscape with a 90
     * degree rotation flag, so the stored width and height are the wrong way
     * round for what the viewer actually sees. Ignoring it exports a portrait
     * recording as a squashed landscape one.
     */
    private fun outputSizeOf(path: String): Pair<Int, Int> {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(path)

            val width = readInt(retriever, MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
            val height = readInt(retriever, MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
            val rotation = readInt(retriever, MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)

            when {
                width <= 0 || height <= 0 -> FALLBACK_WIDTH to FALLBACK_HEIGHT
                // `METADATA_KEY_VIDEO_WIDTH` is the stored width, so a phone
                // video recorded upright and stored landscape needs its
                // dimensions swapped to describe what a viewer actually sees.
                rotation == 90 || rotation == 270 -> height to width
                else -> width to height
            }
        } catch (error: Exception) {
            FALLBACK_WIDTH to FALLBACK_HEIGHT
        } finally {
            try {
                retriever.release()
            } catch (ignored: Exception) {
                // release() throws on some OEM builds when setDataSource failed.
            }
        }
    }

    private fun readInt(retriever: MediaMetadataRetriever, key: Int): Int =
        retriever.extractMetadata(key)?.toIntOrNull() ?: 0
}
