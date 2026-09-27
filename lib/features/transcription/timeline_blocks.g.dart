// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'timeline_blocks.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The project's timeline as blocks on tracks.
///
/// **One list for every kind**, which is what lets one set of gestures move,
/// resize and select any of them: the tracks draw from it, the drag plans on
/// it (`planMove`), and a long press on a track selects what it lists there.

@ProviderFor(timelineContents)
final timelineContentsProvider = TimelineContentsFamily._();

/// The project's timeline as blocks on tracks.
///
/// **One list for every kind**, which is what lets one set of gestures move,
/// resize and select any of them: the tracks draw from it, the drag plans on
/// it (`planMove`), and a long press on a track selects what it lists there.

final class TimelineContentsProvider
    extends
        $FunctionalProvider<
          TimelineContents,
          TimelineContents,
          TimelineContents
        >
    with $Provider<TimelineContents> {
  /// The project's timeline as blocks on tracks.
  ///
  /// **One list for every kind**, which is what lets one set of gestures move,
  /// resize and select any of them: the tracks draw from it, the drag plans on
  /// it (`planMove`), and a long press on a track selects what it lists there.
  TimelineContentsProvider._({
    required TimelineContentsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'timelineContentsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$timelineContentsHash();

  @override
  String toString() {
    return r'timelineContentsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<TimelineContents> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  TimelineContents create(Ref ref) {
    final argument = this.argument as String;
    return timelineContents(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TimelineContents value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TimelineContents>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TimelineContentsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$timelineContentsHash() => r'82eaf37f917d1f0bfa2dde300b2193ad00beaba9';

/// The project's timeline as blocks on tracks.
///
/// **One list for every kind**, which is what lets one set of gestures move,
/// resize and select any of them: the tracks draw from it, the drag plans on
/// it (`planMove`), and a long press on a track selects what it lists there.

final class TimelineContentsFamily extends $Family
    with $FunctionalFamilyOverride<TimelineContents, String> {
  TimelineContentsFamily._()
    : super(
        retry: null,
        name: r'timelineContentsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The project's timeline as blocks on tracks.
  ///
  /// **One list for every kind**, which is what lets one set of gestures move,
  /// resize and select any of them: the tracks draw from it, the drag plans on
  /// it (`planMove`), and a long press on a track selects what it lists there.

  TimelineContentsProvider call(String projectId) =>
      TimelineContentsProvider._(argument: projectId, from: this);

  @override
  String toString() => r'timelineContentsProvider';
}
