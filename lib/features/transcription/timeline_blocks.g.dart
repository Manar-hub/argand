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

/// How long the project runs, past the clips when words still run on after
/// them (`ProjectTimeline.runMsWith`): the ruler's length, and how far
/// playback goes.

@ProviderFor(projectRunMs)
final projectRunMsProvider = ProjectRunMsFamily._();

/// How long the project runs, past the clips when words still run on after
/// them (`ProjectTimeline.runMsWith`): the ruler's length, and how far
/// playback goes.

final class ProjectRunMsProvider extends $FunctionalProvider<int, int, int>
    with $Provider<int> {
  /// How long the project runs, past the clips when words still run on after
  /// them (`ProjectTimeline.runMsWith`): the ruler's length, and how far
  /// playback goes.
  ProjectRunMsProvider._({
    required ProjectRunMsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'projectRunMsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$projectRunMsHash();

  @override
  String toString() {
    return r'projectRunMsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<int> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  int create(Ref ref) {
    final argument = this.argument as String;
    return projectRunMs(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ProjectRunMsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$projectRunMsHash() => r'2029770ba05d27493596fecc97f237db6c18c5b3';

/// How long the project runs, past the clips when words still run on after
/// them (`ProjectTimeline.runMsWith`): the ruler's length, and how far
/// playback goes.

final class ProjectRunMsFamily extends $Family
    with $FunctionalFamilyOverride<int, String> {
  ProjectRunMsFamily._()
    : super(
        retry: null,
        name: r'projectRunMsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// How long the project runs, past the clips when words still run on after
  /// them (`ProjectTimeline.runMsWith`): the ruler's length, and how far
  /// playback goes.

  ProjectRunMsProvider call(String projectId) =>
      ProjectRunMsProvider._(argument: projectId, from: this);

  @override
  String toString() => r'projectRunMsProvider';
}
