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
import android.text.SpannableStringBuilder
import android.text.TextPaint
import android.text.style.MetricAffectingSpan
import android.text.style.CharacterStyle
import android.text.style.ReplacementSpan
import android.text.style.StyleSpan
import android.text.style.UpdateAppearance
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import io.flutter.FlutterInjector
import android.graphics.Matrix
import android.graphics.Typeface
import androidx.media3.common.C
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.common.OverlaySettings
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.Brightness
import androidx.media3.effect.MatrixTransformation
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.Presentation
import androidx.media3.effect.StaticOverlaySettings
import androidx.media3.effect.TextOverlay
import androidx.media3.effect.TextureOverlay
import androidx.media3.common.audio.ChannelMixingAudioProcessor
import androidx.media3.common.audio.ChannelMixingMatrix
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


        /** A look's shadow strength when it names none. */
        const val DEFAULT_SHADOW = 0.4f

        /**
         * The shadow under words at [textSizePx] with dial [strength], as
         * (colour, blur radius, downward offset); null for none. **Mirrors
         * `captionShadowFor` in `lib/core/timeline/item_look.dart`.**
         */
        fun shadowOf(strength: Float, textSizePx: Float): Triple<Int, Float, Float>? {
            if (strength <= 0f) return null
            val s = min(strength, 1f)
            val alpha = ((0.25f + 0.75f * s) * 255f).roundToInt()
            return Triple(alpha shl 24, textSizePx * (0.12f + 0.18f * s), textSizePx * 0.06f)
        }

        /**
         * How far a shadow reaches past its words: its offset plus the blur's
         * visible spread (about 2.5 sigma, sigma = 0.57735 * radius + 0.5).
         */
        fun shadowReach(shadow: Triple<Int, Float, Float>): Int =
            kotlin.math.ceil(shadow.third + 2.5f * (0.57735f * shadow.second + 0.5f)).toInt()

        /**
         * How far up from the bottom the caption sits, in normalised device
         * coordinates where -1 is the bottom edge and 1 the top.
         */
        const val CAPTION_ANCHOR_Y = -0.82f

        /**
         * A text layer's height at scale 1, as a fraction of the output's
         * short edge. **Must match `textLayerFraction` in
         * `lib/core/video/export_options.dart`.**
         */
        const val TEXT_LAYER_FRACTION = 0.06f

        /**
         * How big an image is drawn at scale 1: its longer side this share of
         * the output's shorter edge. `imageExtentFraction` in
         * `video_export.dart`, which the stage sizes by too.
         */
        const val IMAGE_EXTENT_FRACTION = 0.5f

        /**
         * The ink of a word on a highlight box: dark, to read on any colour
         * the box is given. **Must match `_highlightInk` in
         * `stage_editor.dart`.**
         */
        const val HIGHLIGHT_INK = 0xFF111111.toInt()

        /** The mark drawn into a render the user has not asked to unbrand. */
        const val WATERMARK_TEXT = " Argand "

        /**
         * Smaller than a caption, and deliberately so: the watermark is a
         * signature rather than something to read. Still a fraction of the
         * short edge rather than a pixel size, for the same reason captions
         * are -- it has to read the same on a 720p export and a 4K one.
         */
        const val WATERMARK_TEXT_FRACTION = 0.030f

        /** The logo watermark's plate height, as a share of the short edge. */
        const val WATERMARK_PLATE_FRACTION = 0.06f

        const val WATERMARK_COLOR = 0xF2FFFFFF.toInt()
        const val WATERMARK_BACKGROUND = 0x66000000.toInt()

        /**
         * Where the watermark goes when Dart does not say: top-right, in
         * normalised device coordinates. Dart normally sends the corner the
         * user chose (`WatermarkCorner` in `export_options.dart`), which is
         * where these numbers come from.
         */
        const val WATERMARK_ANCHOR_X = 0.94f
        const val WATERMARK_ANCHOR_Y = 0.90f
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

        /**
         * One settings object per placement, built once: every frame asks,
         * and a new object per frame per caption is garbage for nothing.
         */
        private val settingsByPlacement = HashMap<Placement, OverlaySettings>()

        private val hidden = StaticOverlaySettings.Builder()
            .setBackgroundFrameAnchor(0f, CAPTION_ANCHOR_Y)
            .setAlphaScale(0f)
            .build()

        private fun settingsFor(placement: Placement): OverlaySettings =
            settingsByPlacement.getOrPut(placement) {
                StaticOverlaySettings.Builder()
                    .setBackgroundFrameAnchor(placement.x, placement.y)
                    .setScale(placement.scale, placement.scale)
                    .build()
            }

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

            val builder = SpannableStringBuilder()
            val boxed = caption.mode == "highlight" && caption.highlightBox
            // Words with a background cast no shadow (`captionShadowFor`).
            val shadow = if (caption.backgroundArgb == null) {
                shadowOf(caption.shadow, textSizePx.toFloat())
            } else {
                null
            }
            if (shadow != null) ShadowRoomSpan.open(builder, shadowReach(shadow))
            // "John: the words" -- the name leads the line, in its style.
            caption.label?.let { label ->
                val labelStart = builder.length
                builder.append(label).append(": ")
                if (shadow != null) {
                    builder.setSpan(
                        ShadowSpan(shadow),
                        labelStart,
                        builder.length,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
                    )
                }
            }
            val textStart = builder.length
            for ((index, run) in runsAt(caption, presentationTimeUs / 1000).withIndex()) {
                if (index > 0) builder.append(' ')
                val start = builder.length
                builder.append(run.first)
                if (shadow != null && !(boxed && run.second)) {
                    builder.setSpan(
                        ShadowSpan(shadow),
                        start,
                        builder.length,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
                    )
                }
                if (!run.second) continue
                // The word being said -- or, in karaoke, already said.
                if (boxed) {
                    builder.setSpan(
                        BackgroundColorSpan(caption.highlightArgb),
                        start,
                        builder.length,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
                    )
                    builder.setSpan(
                        ForegroundColorSpan(HIGHLIGHT_INK),
                        start,
                        builder.length,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
                    )
                } else {
                    builder.setSpan(
                        ForegroundColorSpan(caption.highlightArgb),
                        start,
                        builder.length,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
                    )
                }
            }

            val textEnd = builder.length
            if (shadow != null) ShadowRoomSpan.close(builder, shadowReach(shadow))

            // The caption's own colour and background carry SPAN_PRIORITY,
            // which sorts them ahead of the per-word spans when drawing -- so
            // a marked word's colour is applied after, and over, the
            // caption's.
            val whole = builder.length
            caption.backgroundArgb?.let {
                builder.setSpan(
                    BackgroundColorSpan(it),
                    textStart,
                    textEnd,
                    Spanned.SPAN_EXCLUSIVE_EXCLUSIVE or Spanned.SPAN_PRIORITY,
                )
            }
            builder.setSpan(
                ForegroundColorSpan(caption.colorArgb),
                0,
                whole,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE or Spanned.SPAN_PRIORITY,
            )
            builder.setSpan(
                AbsoluteSizeSpan(textSizePx),
                0,
                whole,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
            )
            caption.typeface?.let {
                builder.setSpan(FontSpan(it), 0, whole, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
            return SpannableString(builder)
        }

        /**
         * What [caption] shows at [ms]: the runs to draw, each with whether it
         * is marked. **Mirrors `captionRunsAt` in
         * `lib/core/timeline/item_look.dart`**, where the rule is host-tested.
         */
        private fun runsAt(caption: Caption, ms: Long): List<Pair<String, Boolean>> {
            val words = caption.words
            if (words.isEmpty()) return listOf(caption.text to false)
            return when (caption.mode) {
                "karaoke" -> words.map { it.text to (it.startMs <= ms) }
                "highlight" -> words.map { it.text to (it.startMs <= ms && ms < it.endMs) }
                "wordByWord" -> {
                    var current = words.first()
                    for (word in words) if (word.startMs <= ms) current = word
                    listOf(current.text to false)
                }
                else -> listOf(words.joinToString(" ") { it.text } to false)
            }
        }

        override fun getOverlaySettings(presentationTimeUs: Long): OverlaySettings {
            // Each caption sits where its own transcribe layer puts it, so the
            // settings follow whichever caption is showing.
            val caption = activeAt(presentationTimeUs) ?: return hidden
            return settingsFor(caption.placement)
        }
    }

    /**
     * Text layers over this clip that never show at the same time: each in
     * its font and colour, on its background or over its shadow, placed,
     * scaled and turned as the stage showed it.
     *
     * **One overlay per lane, not per text.** Media3 draws every overlay of
     * an effect with its own texture in one shader and refuses more than 15
     * (`OverlayShaderProgram`), so a translation cut into dozens of pieces --
     * or simply many titles -- failed the whole export. Texts that do not
     * overlap in time share one overlay that switches between them, as
     * [CaptionOverlay] does for captions; see [textLanes].
     */
    private class TextLayerOverlay(
        private val items: List<TextItem>,
        private val textSizePx: Int,
    ) : TextOverlay() {

        private val settings = items.map { item ->
            StaticOverlaySettings.Builder()
                .setBackgroundFrameAnchor(item.placement.x, item.placement.y)
                .setScale(item.placement.scale, item.placement.scale)
                // Media3 turns overlays anticlockwise; the stage's clockwise
                // degrees are negated to match.
                .setRotationDegrees(-item.placement.rotation)
                .build()
        }

        private val hidden = StaticOverlaySettings.Builder()
            .setAlphaScale(0f)
            .build()

        private val texts = items.map { spannedOf(it) }

        /** Which item shows at [presentationTimeUs]; -1 for none. */
        private fun indexAt(presentationTimeUs: Long): Int {
            val ms = presentationTimeUs / 1000
            return items.indexOfFirst { ms >= it.startMs && ms < it.endMs }
        }

        // The text asked for when nothing shows: kept as the last one shown,
        // so the bitmap is not rebuilt for a frame nobody sees.
        private var last = 0

        // Padded with spaces, as the stage pads it, so a background reaches
        // past the first and last letters.
        private fun spannedOf(item: TextItem): SpannableString =
            SpannableStringBuilder().run {
            val shadow = if (item.backgroundArgb == null) {
                shadowOf(item.shadow, textSizePx.toFloat())
            } else {
                null
            }
            if (shadow != null) ShadowRoomSpan.open(this, shadowReach(shadow))
            val start = length
            append(" ${item.text} ")
            val end = length
            if (shadow != null) {
                setSpan(ShadowSpan(shadow), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                ShadowRoomSpan.close(this, shadowReach(shadow))
            }
            item.backgroundArgb?.let {
                setSpan(BackgroundColorSpan(it), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
            SpannableString(this)
        }.apply {
            setSpan(
                ForegroundColorSpan(item.colorArgb),
                0,
                length,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
            )
            item.typeface?.let {
                setSpan(FontSpan(it), 0, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
            // Only the default face is made bold; the bundled ones are
            // display weights, and bolding them would smear a fake weight on.
            if (item.bold) {
                setSpan(StyleSpan(Typeface.BOLD), 0, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
            setSpan(
                AbsoluteSizeSpan(textSizePx),
                0,
                length,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
            )
        }

        override fun getText(presentationTimeUs: Long): SpannableString {
            val index = indexAt(presentationTimeUs)
            if (index >= 0) last = index
            return texts[last]
        }

        override fun getOverlaySettings(presentationTimeUs: Long): OverlaySettings {
            val index = indexAt(presentationTimeUs)
            return if (index >= 0) settings[index] else hidden
        }
    }

    /**
     * Pictures over the video, [TextLayerOverlay]'s way: one overlay per lane
     * of images that never show at once, switching between them, so many
     * images cost as few of Media3's 15 overlay slots as can hold them.
     */
    private class ImageLayerOverlay(private val items: List<ImageItem>) : BitmapOverlay() {
        private val settings = items.map { item ->
            StaticOverlaySettings.Builder()
                .setBackgroundFrameAnchor(item.placement.x, item.placement.y)
                .setScale(item.placement.scale, item.placement.scale)
                .setRotationDegrees(-item.placement.rotation)
                .build()
        }

        private val hidden = StaticOverlaySettings.Builder()
            .setAlphaScale(0f)
            .build()

        private var last = 0

        private fun indexAt(presentationTimeUs: Long): Int {
            val ms = presentationTimeUs / 1000
            return items.indexOfFirst { ms >= it.startMs && ms < it.endMs }
        }

        override fun getBitmap(presentationTimeUs: Long): Bitmap {
            val index = indexAt(presentationTimeUs)
            if (index >= 0) last = index
            return items[last].bitmap
        }

        override fun getOverlaySettings(presentationTimeUs: Long): OverlaySettings {
            val index = indexAt(presentationTimeUs)
            return if (index >= 0) settings[index] else hidden
        }
    }

    private data class ImageItem(
        val startMs: Long,
        val endMs: Long,
        val bitmap: Bitmap,
        val placement: Placement,
    )

    /**
     * A picture decoded at the size it is drawn -- its longer side
     * [longerPx] -- once per file for the whole export, however many clips it
     * spans. Null when it cannot be read; the image is then left out.
     */
    private fun decodeImage(path: String, longerPx: Int, cache: MutableMap<String, Bitmap?>): Bitmap? =
        cache.getOrPut(path) {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, bounds)
            val longest = maxOf(bounds.outWidth, bounds.outHeight)
            if (longest <= 0) return@getOrPut null
            var sample = 1
            while (longest / (sample * 2) >= longerPx) sample *= 2
            val decoded = BitmapFactory.decodeFile(
                path,
                BitmapFactory.Options().apply { inSampleSize = sample },
            ) ?: return@getOrPut null
            val scale = longerPx.toFloat() / maxOf(decoded.width, decoded.height)
            Bitmap.createScaledBitmap(
                decoded,
                maxOf(1, (decoded.width * scale).roundToInt()),
                maxOf(1, (decoded.height * scale).roundToInt()),
                true,
            )
        }

    private fun imagesOf(
        raw: Any?,
        longerPx: Int,
        cache: MutableMap<String, Bitmap?>,
    ): List<ImageItem> {
        val list = raw as? List<*> ?: return emptyList()
        return list.mapNotNull { entry ->
            val map = entry as? Map<*, *> ?: return@mapNotNull null
            val path = map["path"] as? String ?: return@mapNotNull null
            val start = (map["startMs"] as? Number)?.toLong() ?: return@mapNotNull null
            val end = (map["endMs"] as? Number)?.toLong() ?: return@mapNotNull null
            if (end <= start) return@mapNotNull null
            val bitmap = decodeImage(path, longerPx, cache) ?: return@mapNotNull null
            ImageItem(start, end, bitmap, placementOf(map))
        }
    }

    private fun imageLanes(items: List<ImageItem>): List<List<ImageItem>> {
        val lanes = mutableListOf<MutableList<ImageItem>>()
        for (item in items.sortedBy { it.startMs }) {
            val lane = lanes.firstOrNull { it.last().endMs <= item.startMs }
            if (lane != null) lane.add(item) else lanes.add(mutableListOf(item))
        }
        return lanes
    }

    /**
     * [items] packed into as few lanes as will hold them with no two in a
     * lane overlapping in time: earliest start first, each into the first
     * lane already clear by then. As many lanes as texts show at once.
     */
    private fun textLanes(items: List<TextItem>): List<List<TextItem>> {
        val lanes = mutableListOf<MutableList<TextItem>>()
        for (item in items.sortedBy { it.startMs }) {
            val lane = lanes.firstOrNull { it.last().endMs <= item.startMs }
            if (lane != null) lane.add(item) else lanes.add(mutableListOf(item))
        }
        return lanes
    }

    /**
     * Draws the app's mark into the corner of every frame.
     *
     * **A real overlay, not a flag.** The toggle in the export dialog removes
     * something that was genuinely composited, which is what makes "remove
     * watermark" an honest offer rather than a switch over nothing.
     *
     * Constant for the whole item, so the text and its settings are built once
     * rather than per frame -- unlike [CaptionOverlay], which has to answer
     * differently as cues come and go.
     */
    private class WatermarkOverlay(
        textSizePx: Int,
        anchorX: Float,
        anchorY: Float,
    ) : TextOverlay() {

        private val settings = StaticOverlaySettings.Builder()
            .setBackgroundFrameAnchor(anchorX, anchorY)
            // The mark's own matching corner is what lands on that point --
            // its top-right in the top-right, its bottom-left in the
            // bottom-left -- so a longer mark grows toward the middle of the
            // frame instead of off its edge.
            .setOverlayFrameAnchor(
                if (anchorX < 0f) -1f else 1f,
                if (anchorY < 0f) -1f else 1f,
            )
            .build()

        private val mark = SpannableString(WATERMARK_TEXT).apply {
            setSpan(
                ForegroundColorSpan(WATERMARK_COLOR),
                0,
                length,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
            )
            setSpan(
                BackgroundColorSpan(WATERMARK_BACKGROUND),
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

        override fun getText(presentationTimeUs: Long): SpannableString = mark

        override fun getOverlaySettings(presentationTimeUs: Long): OverlaySettings =
            settings
    }

    /**
     * The logo watermark: the PNG Dart drew (`ArgandLogo.watermarkPng`),
     * anchored exactly as the word version is.
     */
    private class WatermarkLogoOverlay(
        private val bitmap: Bitmap,
        anchorX: Float,
        anchorY: Float,
    ) : BitmapOverlay() {
        private val settings = StaticOverlaySettings.Builder()
            .setBackgroundFrameAnchor(anchorX, anchorY)
            .setOverlayFrameAnchor(
                if (anchorX < 0f) -1f else 1f,
                if (anchorY < 0f) -1f else 1f,
            )
            .build()

        override fun getBitmap(presentationTimeUs: Long): Bitmap = bitmap

        override fun getOverlaySettings(presentationTimeUs: Long): OverlaySettings =
            settings
    }

    /** One caption, in the clip's own timebase. */
    private data class Caption(
        val startMs: Long,
        val endMs: Long,
        val text: String,
        val colorArgb: Int,
        val placement: Placement,
        val words: List<TimedWord> = emptyList(),
        val mode: String = "standard",
        val highlightArgb: Int = 0xFFFFFFFF.toInt(),
        val highlightBox: Boolean = true,
        val typeface: Typeface? = null,
        val backgroundArgb: Int? = null,
        val shadow: Float = DEFAULT_SHADOW,
        /** The speaker's name, drawn small above the words. */
        val label: String? = null,
    )

    /**
     * Casts the words' drop shadow. Only ever on words with nothing behind
     * them: Android draws a span's background with the same paint, so a
     * shadowed run on a box would shadow the box too.
     */
    private class ShadowSpan(
        private val shadow: Triple<Int, Float, Float>,
    ) : CharacterStyle(), UpdateAppearance {
        override fun updateDrawState(paint: TextPaint) {
            paint.setShadowLayer(shadow.second, 0f, shadow.third, shadow.first)
        }
    }

    /**
     * Invisible room at either end of the words, so their shadow is not cut
     * off at the edge of the bitmap Media3 draws them into -- that bitmap is
     * exactly the text's own bounds.
     *
     * **Symmetric**: as wide at the start as at the end, and as much above
     * the first line as below the last, so the words' centre -- the point
     * the overlay is anchored by -- stays where the stage puts it.
     */
    private class ShadowRoomSpan(
        private val px: Int,
        private val above: Boolean,
    ) : ReplacementSpan() {
        override fun getSize(
            paint: Paint,
            text: CharSequence?,
            start: Int,
            end: Int,
            fm: Paint.FontMetricsInt?,
        ): Int {
            if (fm != null) {
                paint.getFontMetricsInt(fm)
                if (above) {
                    fm.ascent -= px
                    fm.top -= px
                } else {
                    fm.descent += px
                    fm.bottom += px
                }
            }
            return px
        }

        override fun draw(
            canvas: Canvas,
            text: CharSequence?,
            start: Int,
            end: Int,
            x: Float,
            top: Int,
            y: Int,
            bottom: Int,
            paint: Paint,
        ) = Unit

        companion object {
            /** An object-replacement character, standing in for the room. */
            private const val HOLDER = "\uFFFC"

            fun open(builder: SpannableStringBuilder, px: Int) = add(builder, px, true)

            fun close(builder: SpannableStringBuilder, px: Int) = add(builder, px, false)

            private fun add(builder: SpannableStringBuilder, px: Int, above: Boolean) {
                val start = builder.length
                builder.append(HOLDER)
                builder.setSpan(
                    ShadowRoomSpan(px, above),
                    start,
                    builder.length,
                    Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
                )
            }
        }
    }

    /** A caption word, on the item's own clock. */
    private data class TimedWord(val text: String, val startMs: Long, val endMs: Long)

    /**
     * Draws text in a bundled face. `TypefaceSpan(Typeface)` would do, but
     * only from API 28; this works on every version the app runs on.
     */
    private class FontSpan(private val typeface: Typeface) : MetricAffectingSpan() {
        override fun updateDrawState(paint: TextPaint) {
            paint.typeface = typeface
        }

        override fun updateMeasureState(paint: TextPaint) {
            paint.typeface = typeface
        }
    }

    /** Bundled faces, loaded once each. */
    private val typefaces = HashMap<String, Typeface>()

    /**
     * The face for a Flutter font [asset], read from the **same file** the
     * preview draws with (pubspec.yaml's `fonts:`). Null for the default face
     * or a file that cannot be read -- the caption then renders in the
     * default rather than failing the export.
     */
    private fun typefaceFor(asset: String?): Typeface? {
        if (asset.isNullOrBlank()) return null
        typefaces[asset]?.let { return it }
        return try {
            val key = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(asset)
            Typeface.createFromAsset(activity.assets, key).also { typefaces[asset] = it }
        } catch (error: Exception) {
            null
        }
    }

    /**
     * Where an item sits in the frame. **Mirrors `ItemTransform` in
     * `lib/core/timeline/item_transform.dart`**: x and y in normalised device
     * coordinates with up positive, rotation in degrees clockwise as seen.
     */
    private data class Placement(
        val x: Float = 0f,
        val y: Float = 0f,
        val scale: Float = 1f,
        val rotation: Float = 0f,
    ) {
        val isIdentity: Boolean
            get() = x == 0f && y == 0f && scale == 1f && rotation == 0f

        /**
         * The whole-frame map this placement applies, in NDC, for a frame
         * [width] by [height] pixels. **Mirrors `ItemTransform.ndcMatrix`**,
         * where the arithmetic is host-tested: the turn is done in pixels and
         * only the result expressed in NDC, so a non-square frame is not
         * skewed.
         */
        fun ndcMatrix(width: Int, height: Int): Matrix {
            val hw = width / 2f
            val hh = height / 2f
            // Clockwise as seen, in a y-up space, is a negative angle.
            val theta = Math.toRadians(-rotation.toDouble())
            val cos = (Math.cos(theta) * scale).toFloat()
            val sin = (Math.sin(theta) * scale).toFloat()

            return Matrix().apply {
                setValues(
                    floatArrayOf(
                        cos, -sin * hh / hw, x,
                        sin * hw / hh, cos, y,
                        0f, 0f, 1f,
                    ),
                )
            }
        }
    }

    /// A clip's sound on an audio lane: a stretch of its file, and where on
    /// the timeline it plays.
    private data class Sound(
        val path: String,
        val startMs: Long,
        val endMs: Long,
        val projectStartMs: Long,
    ) {
        val projectEndMs: Long get() = projectStartMs + (endMs - startMs)
    }

    /// Mixes a picture's own sound down to nothing, for any channel count, so
    /// the item keeps an audio track -- removing it outright would leave an
    /// audio-only clip with no tracks at all -- and plays silence.
    private fun silence(): ChannelMixingAudioProcessor =
        ChannelMixingAudioProcessor().apply {
            for (channels in 1..8) {
                putChannelMixingMatrix(
                    ChannelMixingMatrix(
                        channels,
                        channels,
                        FloatArray(channels * channels),
                    ),
                )
            }
        }

    private data class TextItem(
        val startMs: Long,
        val endMs: Long,
        val text: String,
        val placement: Placement,
        val colorArgb: Int = 0xFFFFFFFF.toInt(),
        val bold: Boolean = true,
        val typeface: Typeface? = null,
        val backgroundArgb: Int? = null,
        val shadow: Float = DEFAULT_SHADOW,
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
                startExport(
                    clips,
                    fileName,
                    // Absent means "as the source is", which is also what Dart
                    // sends for the Source presets.
                    aspectRatio = (call.argument<Any?>("aspectRatio") as? Number)?.toFloat(),
                    shortEdge = (call.argument<Any?>("shortEdge") as? Number)?.toInt(),
                    watermark = call.argument<Boolean>("watermark") ?: true,
                    watermarkAnchorX = (call.argument<Any?>("watermarkAnchorX") as? Number)
                        ?.toFloat() ?: WATERMARK_ANCHOR_X,
                    watermarkAnchorY = (call.argument<Any?>("watermarkAnchorY") as? Number)
                        ?.toFloat() ?: WATERMARK_ANCHOR_Y,
                    hideVideo = call.argument<Boolean>("hideVideo") ?: false,
                    muteAudio = call.argument<Boolean>("muteAudio") ?: false,
                    watermarkPng = call.argument<ByteArray>("watermarkPng"),
                    result = result,
                )
            }

            "cancel" -> {
                cancelRunning()
                result.success(null)
            }

            // The size a clip is seen at, rotation applied, so Dart can offer
            // only the export sizes the footage can fill. Null when the file
            // cannot be read -- never the render's fallback size, which would
            // be a guess dressed as a measurement.
            "sourceSize" -> {
                val path = call.argument<String>("path")
                if (path.isNullOrBlank()) {
                    result.error("bad_args", "sourceSize needs a path", null)
                    return
                }
                io.execute {
                    val size = probeSize(path)
                    main.post {
                        result.success(
                            size?.let { mapOf("width" to it.first, "height" to it.second) },
                        )
                    }
                }
            }

            else -> result.notImplemented()
        }
    }

    private fun startExport(
        clips: List<Map<String, Any?>>,
        fileName: String,
        aspectRatio: Float?,
        shortEdge: Int?,
        watermark: Boolean,
        watermarkAnchorX: Float,
        watermarkAnchorY: Float,
        hideVideo: Boolean,
        muteAudio: Boolean,
        watermarkPng: ByteArray?,
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
        val source = outputSizeOf(clipPaths.first())
        val size = outputFrameOf(source, aspectRatio, shortEdge)

        // **One presentation stage, not a reframe followed by a resize.**
        // `createForWidthAndHeight` takes the layout mode as well, so the fit
        // and the scale happen in a single resample; chaining two Presentation
        // effects would resample the picture twice for nothing.
        //
        // **Always fit, never crop.** A chosen shape keeps the whole picture
        // and fills the rest of the frame with black: a landscape clip in a
        // 9:16 frame gets bars above and below. Cropping silently threw away
        // the sides of every shot, which is a reframe the user never made.
        // The preview draws the same fit (`VideoCanvas`).
        val presentation: Effect = Presentation.createForWidthAndHeight(
            size.first,
            size.second,
            Presentation.LAYOUT_SCALE_TO_FIT,
        )
        // Sized against the short edge of the *output*, so the caption reads
        // the same whatever the source was.
        val textSizePx =
            (min(size.first, size.second) * CAPTION_TEXT_FRACTION).roundToInt()
        val watermarkSizePx =
            (min(size.first, size.second) * WATERMARK_TEXT_FRACTION).roundToInt()
        // The logo scaled to its plate height on this frame.
        val watermarkLogo = watermarkPng?.let { bytes ->
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.let { decoded ->
                val height = maxOf(
                    8,
                    (min(size.first, size.second) * WATERMARK_PLATE_FRACTION).roundToInt(),
                )
                val width = maxOf(1, (decoded.width * height.toFloat() / decoded.height).roundToInt())
                Bitmap.createScaledBitmap(decoded, width, height, true)
            }
        }
        val textLayerSizePx =
            (min(size.first, size.second) * TEXT_LAYER_FRACTION).roundToInt()
        val imageLongerPx =
            (min(size.first, size.second) * IMAGE_EXTENT_FRACTION).roundToInt()
        val decodedImages = HashMap<String, Bitmap?>()

        val items = clips.map { clip ->
            val path = clip["path"] as String
            val captions = captionsOf(clip["captions"])

            // **Presentation first, then the overlay.** Effects run in order,
            // so putting the caption first would size it against the source
            // frame and then scale it with everything else.
            val videoEffects = mutableListOf<Effect>(presentation)

            // **The clip's framing, after the fit.** Presentation has already
            // made the frame its final size, so this moves, turns and scales
            // the fitted picture inside that frame -- zooming in crops at the
            // edge, zooming out leaves black -- exactly as the stage draws it.
            // Skipped when untouched: an identity pass is a resample for
            // nothing.
            val framing = placementOf(clip["framing"])
            if (!framing.isIdentity) {
                val matrix = framing.ndcMatrix(size.first, size.second)
                videoEffects.add(MatrixTransformation { matrix })
            }

            // The video track hidden on the timeline: the picture goes to
            // black, and the overlays added below are still drawn over it.
            if (hideVideo) videoEffects.add(Brightness(-1f))

            // One effect carrying both overlays rather than two effects: each
            // OverlayEffect is its own GL pass over the frame, and there is no
            // reason for the mark to cost a second one.
            val overlays = mutableListOf<TextureOverlay>()
            // Images first, under every word -- the order the stage stacks
            // them in.
            for (lane in imageLanes(imagesOf(clip["images"], imageLongerPx, decodedImages))) {
                overlays.add(ImageLayerOverlay(lane))
            }
            // Texts before captions, so a caption drawn over a title stays
            // readable -- the order the stage stacks them in.
            for (lane in textLanes(textsOf(clip["texts"]))) {
                overlays.add(TextLayerOverlay(lane, textLayerSizePx))
            }
            if (captions.isNotEmpty()) {
                overlays.add(CaptionOverlay(captions, textSizePx))
            }
            if (watermark) {
                // The logo when Dart drew one, else the word.
                val logo = watermarkLogo
                overlays.add(
                    if (logo != null) {
                        WatermarkLogoOverlay(logo, watermarkAnchorX, watermarkAnchorY)
                    } else {
                        WatermarkOverlay(watermarkSizePx, watermarkAnchorX, watermarkAnchorY)
                    },
                )
            }
            if (overlays.isNotEmpty()) {
                videoEffects.add(OverlayEffect(overlays.toList()))
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

            // **The picture's own sound only when it plays with the picture.**
            // A sound that was trimmed, carried past its picture (J/L cut),
            // removed, or whose track is hidden is silenced here -- at zero
            // gain, which keeps a track, so an audio-only clip still has one
            // -- and, when it is to be heard, played from an audio lane below.
            val audio = clip["audio"] as? Map<*, *>
            val inline = audio?.get("inline") == true && !muteAudio
            EditedMediaItem.Builder(mediaItem)
                .setEffects(
                    Effects(
                        if (inline) emptyList() else listOf(silence()),
                        videoEffects,
                    ),
                )
                .build()
        }

        // Sounds not played with their pictures, each at its own place on the
        // timeline, packed into as few lanes as hold them without overlap:
        // one sequence per lane, gaps where it is quiet, mixed together.
        val sounds = if (muteAudio) emptyList() else clips.mapNotNull { clip ->
            val audio = clip["audio"] as? Map<*, *> ?: return@mapNotNull null
            if (audio["inline"] == true) return@mapNotNull null
            val start = (audio["startMs"] as? Number)?.toLong() ?: return@mapNotNull null
            val end = (audio["endMs"] as? Number)?.toLong() ?: return@mapNotNull null
            val at = (audio["projectStartMs"] as? Number)?.toLong() ?: return@mapNotNull null
            if (end <= start) return@mapNotNull null
            Sound(clip["path"] as String, start, end, at)
        }
        val audioLanes = mutableListOf<MutableList<Sound>>()
        for (sound in sounds.sortedBy { it.projectStartMs }) {
            val lane = audioLanes.firstOrNull { it.last().projectEndMs <= sound.projectStartMs }
            if (lane != null) lane.add(sound) else audioLanes.add(mutableListOf(sound))
        }
        val audioSequences = audioLanes.map { lane ->
            // Forced audio, which is what lets a lane open with a gap.
            val builder = EditedMediaItemSequence.Builder(setOf(C.TRACK_TYPE_AUDIO))
            var cursor = 0L
            for (sound in lane) {
                if (sound.projectStartMs > cursor) {
                    builder.addGap((sound.projectStartMs - cursor) * 1000)
                }
                val item = MediaItem.Builder()
                    .setUri(File(sound.path).toURI().toString())
                    .setClippingConfiguration(
                        MediaItem.ClippingConfiguration.Builder()
                            .setStartPositionMs(sound.startMs)
                            .setEndPositionMs(sound.endMs)
                            .build(),
                    )
                    .build()
                builder.addItem(
                    EditedMediaItem.Builder(item).setRemoveVideo(true).build(),
                )
                cursor = sound.projectEndMs
            }
            builder.build()
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
        val picture = EditedMediaItemSequence.Builder(
            setOf(C.TRACK_TYPE_AUDIO, C.TRACK_TYPE_VIDEO),
        ).addItems(items).build()
        // The picture's sequence first, then every audio lane; Media3 mixes
        // the audio of all of them.
        val composition = Composition.Builder(listOf(picture) + audioSequences)
            .build()

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
                placement = placementOf(map, defaultY = CAPTION_ANCHOR_Y),
                words = (map["words"] as? List<*>).orEmpty().mapNotNull { raw ->
                    val word = raw as? Map<*, *> ?: return@mapNotNull null
                    TimedWord(
                        text = word["text"] as? String ?: return@mapNotNull null,
                        startMs = (word["startMs"] as? Number)?.toLong() ?: 0L,
                        endMs = (word["endMs"] as? Number)?.toLong() ?: 0L,
                    )
                },
                mode = map["mode"] as? String ?: "standard",
                highlightArgb = (map["highlightArgb"] as? Number)?.toInt()
                    ?: 0xFFFFFFFF.toInt(),
                highlightBox = map["highlightBox"] != false,
                backgroundArgb = (map["backgroundArgb"] as? Number)?.toInt(),
                shadow = (map["shadow"] as? Number)?.toFloat() ?: DEFAULT_SHADOW,
                typeface = typefaceFor(map["font"] as? String),
                label = (map["label"] as? String)?.takeIf { it.isNotBlank() },
            )
        }
    }

    private fun textsOf(raw: Any?): List<TextItem> {
        val list = raw as? List<*> ?: return emptyList()

        return list.mapNotNull { entry ->
            val map = entry as? Map<*, *> ?: return@mapNotNull null
            val text = map["text"] as? String ?: return@mapNotNull null
            if (text.isBlank()) return@mapNotNull null

            val start = (map["startMs"] as? Number)?.toLong() ?: return@mapNotNull null
            val end = (map["endMs"] as? Number)?.toLong() ?: return@mapNotNull null
            if (end <= start) return@mapNotNull null

            TextItem(
                startMs = start,
                endMs = end,
                text = text,
                placement = placementOf(map),
                colorArgb = (map["colorArgb"] as? Number)?.toInt() ?: 0xFFFFFFFF.toInt(),
                bold = map["bold"] != false,
                backgroundArgb = (map["backgroundArgb"] as? Number)?.toInt(),
                shadow = (map["shadow"] as? Number)?.toFloat() ?: DEFAULT_SHADOW,
                typeface = typefaceFor(map["font"] as? String),
            )
        }
    }

    /** Reads a placement, falling back per field to the identity. */
    private fun placementOf(raw: Any?, defaultY: Float = 0f): Placement {
        val map = raw as? Map<*, *> ?: return Placement(y = defaultY)
        fun read(key: String, fallback: Float) =
            (map[key] as? Number)?.toFloat() ?: fallback

        return Placement(
            x = read("x", 0f),
            y = read("y", defaultY),
            scale = read("scale", 1f),
            rotation = read("rotation", 0f),
        )
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
    private fun outputSizeOf(path: String): Pair<Int, Int> =
        probeSize(path) ?: (FALLBACK_WIDTH to FALLBACK_HEIGHT)

    /** The clip's size as seen, rotation applied, or null if unreadable. */
    private fun probeSize(path: String): Pair<Int, Int>? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(path)

            val width = readInt(retriever, MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
            val height = readInt(retriever, MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
            val rotation = readInt(retriever, MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)

            when {
                width <= 0 || height <= 0 -> null
                // `METADATA_KEY_VIDEO_WIDTH` is the stored width, so a phone
                // video recorded upright and stored landscape needs its
                // dimensions swapped to describe what a viewer actually sees.
                rotation == 90 || rotation == 270 -> height to width
                else -> width to height
            }
        } catch (error: Exception) {
            null
        } finally {
            try {
                retriever.release()
            } catch (ignored: Exception) {
                // release() throws on some OEM builds when setDataSource failed.
            }
        }
    }

    /**
     * The frame to render into, from the source size and what was chosen.
     *
     * **Mirrors `exportFrameFor` in `lib/core/video/export_options.dart`**,
     * where the same arithmetic is covered by host tests; the two are checked
     * against each other by reading the dimensions back off a finished export.
     * Duplicated rather than round-tripped because Dart cannot see a clip's
     * pixel size without asking this side for it first.
     *
     * [shortEdge] names the short edge rather than the height, so a quality
     * preset means the same thing in both orientations.
     */
    private fun outputFrameOf(
        source: Pair<Int, Int>,
        aspectRatio: Float?,
        shortEdge: Int?,
    ): Pair<Int, Int> {
        val ratio = aspectRatio ?: (source.first.toFloat() / source.second.toFloat())
        if (ratio <= 0f) return source

        // Never above the source's own short edge: a larger frame would only
        // be an upscale. Dart already offers nothing bigger than the source;
        // this holds even when Dart could not learn the source's size.
        val sourceShort = min(source.first, source.second)
        val short = min(shortEdge ?: sourceShort, sourceShort)

        // Which edge is short depends on the *output* shape, not the source's.
        val width = if (ratio < 1f) short else (short * ratio).roundToInt()
        val height = if (ratio < 1f) (short / ratio).roundToInt() else short

        return even(width) to even(height)
    }

    /**
     * H.264 rejects odd dimensions outright, so a ratio landing on one is
     * nudged down rather than failing the export.
     */
    private fun even(value: Int): Int = if (value % 2 == 0) value else value - 1

    private fun readInt(retriever: MediaMetadataRetriever, key: Int): Int =
        retriever.extractMetadata(key)?.toIntOrNull() ?: 0
}
