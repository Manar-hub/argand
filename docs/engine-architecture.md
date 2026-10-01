# Engine architecture

The decisions behind Argand's on-device engines, and the measurements that
settled them. The app layout is described in [architecture.md](architecture.md).

## Transcription

I picked whisper.cpp through the `whisper_ggml_plus` package. It handles the
FFI bridge, runs inference off the UI isolate and manages native memory.

The app bundles a quantized **base** model. It is accurate enough for spoken
video and small enough to ship inside the APK. Larger models, like small and
medium and more, are optional downloads from Settings > Transcription models.

The package has a fork in `packages/whisper_ggml_plus/`. Version
1.5.2 declared several parameters that its native code never read:
`no_fallback`, `suppress_nst`, the sampling strategy, `initial_prompt` and
the progress callback. The fork passes them through, and every change is
marked `// FORK:`.

The settings chosen, and why:

| Setting | Value | Reason |
| --- | --- | --- |
| `flash_attn` | on | It runs on the CPU backend too. Word error rate went from 22.3% to 20.1% and a reference clip from 10.2 s to 6.5 s. |
| `n_threads` | 4 | A good fit for current phone CPUs. |
| `strategy` | greedy | Beam search is more accurate (12.3% vs 22.3%), but it changes sentence boundaries, which diarization depends on. |
| `split_on_word`, `max_len: 1` | on | They give word-level timestamps and cost no accuracy, because they only segment after decoding. |
| `no_fallback` | off | Temperature fallback is the only thing that triggers whisper.cpp's repetition detector. With it off, looping output reached the transcript. |
| `suppress_nst` | on | It stops tags like `[BLANK_AUDIO]` from appearing as text. |
Word timestamps come from DTW alignment and can drift by a few tens of
milliseconds, so seeking and caption grouping allow a small tolerance.

## Voice activity detection

Before decoding, whisper.cpp runs Silero VAD so only speech is transcribed.
The Silero model already ships inside the package, so it adds nothing to the
app size.

Upstream turned VAD off whenever word timestamps were on. I checked the
source: the segment accessors the fork reads do map times back through VAD's
table, so I removed that guard. An integration test checks that every word
time stays in order and inside the media's length.

What VAD did in my tests:
- no more text invented over silence;
- far fewer repetition loops (184 repeated segments down to 22);
- byte-identical transcripts on clean audio.

It does not fix a wrongly detected language, which is why the transcribe
dialog has a language picker.

## Noise suppression, tried and left out

I built a GTCRN denoiser pass with Sherpa-ONNX and measured it. On clean
speech it changed correct words into wrong ones ("real life" became "marine
life"), because it rebuilds the waveform instead of filtering it. VAD fixed
the repetition problem it was meant for, without that cost, so the denoiser
is not part of the transcription path.

## Speaker detection (diarization)

Sherpa-ONNX runs two models:
- `pyannote-segmentation-3.0.onnx` (5.7 MB) finds where the speaker changes;
- `campplus-speaker-embedding.onnx` (27 MB) decides who each stretch sounds like.

Clustering compares the whole file at once, so it can't be streamed in
chunks. Files longer than 30 minutes skip diarization rather than risk
running out of memory. They still get a full transcript.

I measured the clustering threshold instead of keeping the default. At 0.5 it
split one voice into several; 0.75 works on my labelled test clips.

Transcription and diarization produce different boundaries.
`speaker_assignment.dart` matches each word to the speaker span it overlaps
most. CAM++ embeddings then recheck short, uncertain regions against the
audio. I tried and removed three other attribution rules (sentence overlap, a
straddle guard, and a Viterbi pass over sentences), because each one scored
worse than this on labelled data. Accuracy is scored per word against
time-stamped labels.

## Decoding audio

The `audio_decoder` package uses the phone's own decoders (MediaCodec on
Android), so the app needs no FFmpeg and carries no GPL licensing risk.
whisper.cpp needs 16 kHz mono 16-bit WAV, and the package produces that
directly.

I also forked this package (`packages/audio_decoder/`). HE-AAC videos
transcribed as fluent nonsense because the extractor reports the AAC core
rate (22,050 Hz) while the decoder outputs double that. Upstream resampled
from the wrong number, so audio came out at half speed. The fork reads the
real rate from the decoder's output format. Two guards now catch this kind
of error: the import compares the WAV's duration to the source's, and the
native layer rejects any WAV that isn't 16 kHz.

## Captions stay text until export

Words are stored as rows with their timing and speaker. Captions are grouped
from those rows when they are read, and there is no captions table. That
keeps tap-to-seek, editing, undo and style changes non-destructive. Captions
only become pixels in the exported video.

Caption breaks follow, in order:
1. a speaker change;
2. the end of a sentence;
3. the end of a clause, once the caption can stand alone;
4. a pause of 700 ms or more;
5. about 84 characters or 6 seconds.

Undo and redo use a log of individual edits, each with its inverse, rather
than snapshots of the whole document.

Speaker colours come from the diarization index, so a speaker is the same
colour in the transcript and on the video without storing anything.

## Video export

Export uses Android's Media3 Transformer through a platform channel. It
handles trimming, joining clips, audio mixing and overlays, so captions, text,
images and the watermark are drawn in one pass.
