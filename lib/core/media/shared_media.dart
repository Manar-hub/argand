import 'dart:async';

import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'shared_media.g.dart';

/// A file the OS handed to this app through the system share sheet.
///
/// [uri] is a `content://` URI, not a path — Dart cannot open it, and the read
/// grant behind it belongs to the Activity and is revocable. [copy] is how the
/// bytes actually get out.
class SharedMedia {
  const SharedMedia({required this.uri, required this.name});

  final String uri;

  /// The name the sharing app gave the file. Used for the project title and,
  /// through its extension, to pick a container parser.
  final String name;
}

/// The bridge to the Android Sharesheet.
///
/// A **MethodChannel**, which is Flutter's async bridge to native Kotlin — the
/// mechanism CLAUDE.md §8 names for OS-level services. It is the right tool
/// here for a reason that is not about preference: the incoming file arrives as
/// a `content://` URI, which has no filesystem path at all, so only native code
/// can resolve its name or read its bytes.
///
/// Two calls rather than one, deliberately. [initialShare] and [shares] carry
/// only metadata and are cheap; [copy] does the byte copy and runs on a
/// background executor on the native side, because a shared video routinely
/// runs to hundreds of megabytes and copying it inline would block the main
/// thread long enough to ANR.
class SharedMediaChannel {
  const SharedMediaChannel();

  static const _channel = MethodChannel('argand/shared_media');

  /// The share that launched the app, or null on an ordinary start.
  ///
  /// **Taken, not read**: the native side clears it once handed over, so a hot
  /// restart cannot re-import the same file. Asked for by Dart when it is ready
  /// rather than pushed, which removes the race a cold start would otherwise
  /// have between the engine starting and a listener being attached.
  Future<SharedMedia?> initialShare() async {
    final result = await _channel.invokeMapMethod<String, String>(
      'takeInitialShare',
    );
    return _read(result);
  }

  /// Shares that arrive while the app is already running.
  ///
  /// A broadcast stream so more than one listener can attach without the first
  /// consuming the event; in practice the library screen is the only one.
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
  ///
  /// The file lands in the app's cache directory. The caller is expected to
  /// adopt it into permanent storage and delete it — cache is the right place
  /// for a file that is about to be moved, and the OS may clear it under
  /// storage pressure, which for a half-finished import is the correct outcome.
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
