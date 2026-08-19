import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/whisper/whisper_service.dart';

void main() {
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const WhisperScreen(),
    );
  }
}

class WhisperScreen extends ConsumerStatefulWidget {
  const WhisperScreen({super.key});

  @override
  ConsumerState<WhisperScreen> createState() => _WhisperScreenState();
}

class _WhisperScreenState extends ConsumerState<WhisperScreen> {
  String status = 'Ready';

  Timer? _progressTimer;

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  Future<void> _runWhisper() async {
    setState(() => status = 'Loading model + transcribing...');
    final stopwatch = Stopwatch()..start();
    try {
      final service = ref.read(whisperServiceProvider);

      // Poll the native progress counter while inference runs in its own
      // isolate. Proves the forked progress_callback is actually firing.
      _progressTimer?.cancel();
      _progressTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!mounted) return;
        setState(() => status = 'Transcribing... ${service.progressPercent}%');
      });
      // Phase-0 wiring proof: a real WAV pushed to the device at a fixed
      // path (see docs/progress.md). Phase 1 replaces this with real file
      // import via audio_decoder.
      final result = await service.transcribeWav('/data/local/tmp/test_speech.wav');
      stopwatch.stop();
      _progressTimer?.cancel();

      final words = result.segments ?? const [];
      final wordLines = words
          .map((w) => '${w.fromTs.inMilliseconds}-${w.toTs.inMilliseconds}ms: "${w.text}"')
          .join('\n');

      setState(() => status =
          'Done in ${stopwatch.elapsedMilliseconds}ms\n\nText: ${result.text}\n\nWords:\n$wordLines');
    } catch (e) {
      stopwatch.stop();
      _progressTimer?.cancel();
      setState(() => status = 'Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Whisper Engine Test')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(status, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _runWhisper,
                child: const Text('Transcribe test file'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
