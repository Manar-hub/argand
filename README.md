# Argand

Argand is an easy and free tool dedicated for transcribing, diarizing, and translating videos, exported in MP4, SRT, TML and more.
All done on your device. High in accuracy, fast, and unlimited.

<p align="center">
  <img src="./assets/source_images/logo.png" width="200" height="200" alt="Argand Logo" />
  <img src="https://github.com/user-attachments/assets/15a20a85-3c6a-4a45-b98e-1ea89bd7d527" width="605" height="200" alt="Argand Logo" />
</p>

<p align="center">
  <img width="200" height="430" src="https://github.com/user-attachments/assets/01ee6994-0de0-46aa-b090-4cf3b11f05ce" />
  <img width="200" height="430" src="https://github.com/user-attachments/assets/d804794a-d87e-44e0-9f27-7fb2eaf13c5d" />
  <img width="200" height="430" src="https://github.com/user-attachments/assets/b759bed0-6793-42f4-846a-4e87964ff351" />
  <img width="200" height="430" src="https://github.com/user-attachments/assets/0a3ab3b3-9bf2-4448-9745-3bcf1530145b" />
</p>

<p align="center">
  <a href="https://www.youtube.com/watch?v=fZlcj5yKuvk">
    <picture>
      <source media="(max-width: 1000px)" srcset="https://github.com/user-attachments/assets/8ddba2bd-9f36-4f77-b872-ff84c58e881f">
      <img src="https://github.com/user-attachments/assets/8ddba2bd-9f36-4f77-b872-ff84c58e881f" width="220" height="473" alt="Argand Demo Preview">
    </picture>
  </a>
  <br><br>
  <a href="https://www.youtube.com/watch?v=fZlcj5yKuvk">
    <img src="https://img.shields.io/badge/YouTube-Watch_Full_Demo-FF0000?style=for-the-badge&logo=youtube&logoColor=white" alt="Watch on YouTube" />
  </a>
</p>

**_Demo Note:_**
This demo is minimally edited to authentically showcase the app's raw performance and transcription quality. 
The sample footage is by @alberta.tech on Instagram, utilized for technical demonstration under fair use.

## Why Argand

Putting captions on a video you shot on your phone shouldn't mean uploading it, signing up, or buying credits. Argand does the whole job on the device:

- **Private by construction.** Transcription, speaker detection and translation run locally. There is no account and no server that ever sees your footage.
- **Edit the words, not the waveform.** In script mode the transcript *is* the edit: tap a word to jump there, retype a line, reassign a turn to the right speaker.
- **Speakers are first-class.** Each voice gets a name and a colour that carry through the transcript, the captions and the export.

## Key Features

- **Transcription on the device.** whisper.cpp runs offline with a with any model you wish to add.
- **Speaker detection.** Each speaker gets a name and a colour, in the transcript and in the captions.
- **Script mode.** Tap a word to jump to it, retype a line seamlessly, or give a turn to the right speaker.
- **Timeline editor.** Split, trim and remove clips, move audio separately (J and L cuts), and add text and images. Undo and redo cover every edit.
- **Captions you can place and style.** Drag, resize and zoom captions on the preview. Choose the font, colour, background, shadow and karaoke highlight for one line, one speaker or every caption.
- **Translation.** Translated captions appear under the original, translated on the device with ML Kit.
- **Export.** MP4 high resolution support with the captions drawn in, or SRT, VTT, XML, FCPXML, TML subtitle files.
- **Argand Pro.** A one-time purchase through RevenueCat. Pro removes the export watermark, and watching a rewarded ad removes it for a single export.
- **Privacy.** No account, no cloud processing, no analytics, your data is yours.

## Tech stack

| Part | What it uses |
| --- | --- |
| App | Flutter, Riverpod (code generation), Drift (SQLite) |
| Transcription | whisper.cpp through a patched fork of `whisper_ggml_plus` |
| Speakers | Sherpa-ONNX: pyannote segmentation and CAM++ embeddings |
| Audio decoding | A patched fork of `audio_decoder` using the phone's decoders (no FFmpeg) |
| Translation | Google ML Kit, on-device |
| Video export | Android Media3 Transformer |
| Purchases and ads | RevenueCat, Google AdMob |

The reasoning behind these choices is in [docs/engine-architecture.md](docs/engine-architecture.md),
and the code layout is in [docs/architecture.md](docs/architecture.md).

## Run it

The app targets Android. You need Flutter 3.47 or newer and Android Studio,
with the NDK and CMake installed from the SDK Manager.

1. Clone the repo:

   ```sh
   git clone https://github.com/Manar-hub/argand.git
   cd argand
   ```

2. Download the whisper base model into `assets/models/` or any model you wish to use. Base model for example:

   ```sh
   curl -L -o assets/models/ggml-base.bin https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin
   ```

   Any other `ggml-*.bin` or `whisper-*.gguf` model placed there shows up in
   Settings > Transcription models after the next build.

3. Add your RevenueCat key. Copy `.env.example` to `.env` and paste a public
   SDK key. A Test Store key works, and test purchases cost nothing:

   ```sh
   cp .env.example .env
   ```

   Without a key the app still runs, and Pro shows as unavailable.

4. Get packages and generate code:

   ```sh
   flutter pub get
   dart run build_runner build --delete-conflicting-outputs
   flutter gen-l10n
   ```

5. Start an emulator or connect a phone, then run:

   ```sh
   flutter run --dart-define-from-file=.env
   ```

important: Depending on model choice, if using an Android Emulator, increase the AVD RAM to at least 4GB–6GB to prevent Out-Of-Memory errors during local AI transcription with ultra heavy models. Medium_q4 whisper model was run on only 2GB of AVD RAM.

Ads use Google's public test IDs. 
In a Test Store build, long-press the logo on the home screen to reset Pro and buy it again.

Tests: `flutter test`.

## Project layout

```
argand/
├── lib/
│   ├── main.dart            start-up: theme, RevenueCat, ads
│   ├── core/                engines, database, timeline model, payments, theme
│   ├── features/            screens: library, editor, settings, paywall
│   └── l10n/                UI strings
├── android/                 native video export (Media3) and launcher icons
├── packages/                patched whisper.cpp and audio decoder plugins
├── assets/                  models, fonts, logo
├── docs/                    architecture and engine decisions
├── test/                    host tests
└── integration_test/        on-device tests
```

## The story
Transcription and diarization are not new concepts, but just like many other features, companies heavily gatekeep or limit access to tools that should be free. 
Phones are underestimated for how much they can perform, and running ML models is not fiction anymore, and this is where it started with me, experimenting with using a phone's capabilities.
Even mid-range phones can now run billion-parameter models without consuming many resources, more or less like playing a video game. 
I was personally shocked at the results with my project, high accuracy and on par with cloud services if not better sometimes. The emulator, which is used for the demo, was on a **2gb of ram constraint** yet it was able to run medium whisper model!

### Challenges
The road was not clear. At many times I was asking myself: *Am I running into a physical limitation of existing tools, or am I doing something wrong?* The code compiled and gave confident results, but they weren't quite right. 
Despite limited time, I had to brute-force my solutions: 
-Tested industry-standard tools like **GTCRN**, but results were unacceptable. 
-Tuned dials up and down for **pyannote** and **Whisper**, introduced **CAM++**, and analyzed bit-identical files down to milliseconds of silence between speakers.
Discovered the audio decoder was reading incorrect sample rates from files which led me to **fork the native whisper engine** directly because it was blind to my settings all along.

### What I learned
A lot. I never dealt with these specific tools before, putting it under time pressure and starting three weeks late to the hackathon made me learn not only to ship even more quickly, but to also accelerate my learning methods. That regardless of the pressure and decision fatigue I faced all throughout, it was definitely worth it seeing the project come to life. I learned to also use AI along the way. If I don't , it's a losing race. The app would still never come to life with one prompt, not even with a hundred if the person doesn't know what they're doing.

## Privacy

See [PRIVACY_POLICY.md](PRIVACY_POLICY.md). The same text is in the app under Settings.

## License

MIT. See [LICENSE](LICENSE).
