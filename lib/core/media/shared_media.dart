import 'dart:async';

import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'shared_media.g.dart';

/// A file the OS handed to this app through the system share sheet.
class SharedMedia {
  const SharedMedia({required this.uri, required this.name});

  final String uri;

  /// The name the sharing app gave the file. Used for the project title and,
  /// through its extension, to pick a container parser.
  final String name;
}

/// The bridge to the Android Sharesheet.
class SharedMediaChannel {
  const SharedMediaChannel();

  static const _channel = MethodChannel('argand/shared_media');

  /// The share that launched the app, or null on an ordinary start.
  Future<SharedMedia?> initialShare() async {
    final result = await _channel.invokeMapMethod<String, String>(
      'takeInitialShare',
    );
    return _read(result);
  }

  /// Shares that arrive while the app is already running.
  Stream<SharedMedia> shares() {
    final controller = StreamController<SharedMedia>.broadcast();

    _channel.setMethodCallHandler((call) async {
      if (call.method != 'share') return null;
      final media = _read(
        (call.arguments as Map?)?.cast<String, String>(),
      );
      if (media != null) controller.add(media);
      return null;
    });

    controller.onCancel = () => _channel.setMethodCallHandler(null);
    return controller.stream;
  }

  /// Copies [media] out of the content provider and returns a real path.
  Future<String?> copy(SharedMedia media) {
    return _channel.invokeMethod<String>('copySharedMedia', {
      'uri': media.uri,
      'name': media.name,
    });
  }

  SharedMedia? _read(Map<String, String>? raw) {
    if (raw == null) return null;
    final uri = raw['uri'];
    final name = raw['name'];
    if (uri == null || uri.isEmpty) return null;
    return SharedMedia(uri: uri, name: name ?? 'shared');
  }
}

@Riverpod(keepAlive: true)
SharedMediaChannel sharedMediaChannel(Ref ref) => const SharedMediaChannel();
