// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'video_settings.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// A project's video settings, changed live.

@ProviderFor(ProjectVideoSettings)
final projectVideoSettingsProvider = ProjectVideoSettingsFamily._();

/// A project's video settings, changed live.
final class ProjectVideoSettingsProvider
    extends $AsyncNotifierProvider<ProjectVideoSettings, VideoSettings> {
  /// A project's video settings, changed live.
  ProjectVideoSettingsProvider._({
    required ProjectVideoSettingsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'projectVideoSettingsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$projectVideoSettingsHash();

  @override
  String toString() {
    return r'projectVideoSettingsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ProjectVideoSettings create() => ProjectVideoSettings();

  @override
  bool operator ==(Object other) {
    return other is ProjectVideoSettingsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$projectVideoSettingsHash() =>
    r'1a2ef3abf71e1c90415b1f384647088a3d214f8a';

/// A project's video settings, changed live.

final class ProjectVideoSettingsFamily extends $Family
    with
        $ClassFamilyOverride<
          ProjectVideoSettings,
          AsyncValue<VideoSettings>,
          VideoSettings,
          FutureOr<VideoSettings>,
          String
        > {
  ProjectVideoSettingsFamily._()
    : super(
        retry: null,
        name: r'projectVideoSettingsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// A project's video settings, changed live.

  ProjectVideoSettingsProvider call(String projectId) =>
      ProjectVideoSettingsProvider._(argument: projectId, from: this);

  @override
  String toString() => r'projectVideoSettingsProvider';
}

/// A project's video settings, changed live.

abstract class _$ProjectVideoSettings extends $AsyncNotifier<VideoSettings> {
  late final _$args = ref.$arg as String;
  String get projectId => _$args;

  FutureOr<VideoSettings> build(String projectId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<VideoSettings>, VideoSettings>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<VideoSettings>, VideoSettings>,
              AsyncValue<VideoSettings>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// The pixel size of the project's footage: its first clip, which is what the
/// render sizes every export from.

@ProviderFor(projectSourceSize)
final projectSourceSizeProvider = ProjectSourceSizeFamily._();

/// The pixel size of the project's footage: its first clip, which is what the
/// render sizes every export from.

final class ProjectSourceSizeProvider
    extends
        $FunctionalProvider<
          AsyncValue<({int height, int width})?>,
          ({int height, int width})?,
          FutureOr<({int height, int width})?>
        >
    with
        $FutureModifier<({int height, int width})?>,
        $FutureProvider<({int height, int width})?> {
  /// The pixel size of the project's footage: its first clip, which is what the
  /// render sizes every export from.
  ProjectSourceSizeProvider._({
    required ProjectSourceSizeFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'projectSourceSizeProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$projectSourceSizeHash();

  @override
  String toString() {
    return r'projectSourceSizeProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<({int height, int width})?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<({int height, int width})?> create(Ref ref) {
    final argument = this.argument as String;
    return projectSourceSize(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ProjectSourceSizeProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$projectSourceSizeHash() => r'763608ab87d4b700d8a1bc577bfa56c623b37ede';

/// The pixel size of the project's footage: its first clip, which is what the
/// render sizes every export from.

final class ProjectSourceSizeFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<({int height, int width})?>,
          String
        > {
  ProjectSourceSizeFamily._()
    : super(
        retry: null,
        name: r'projectSourceSizeProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The pixel size of the project's footage: its first clip, which is what the
  /// render sizes every export from.

  ProjectSourceSizeProvider call(String projectId) =>
      ProjectSourceSizeProvider._(argument: projectId, from: this);

  @override
  String toString() => r'projectSourceSizeProvider';
}
