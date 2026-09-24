// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'video_settings_panel.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Whether a project's video settings are open, and on which item.
///
/// A provider rather than widget state because two separate parts of the
/// screen answer to it: the transport row, which hides its buttons, and the
/// body, which shows the panel. It also remembers the last item for as long
/// as the project is open, so reopening the panel lands where it was left.

@ProviderFor(VideoSettingsPanelController)
final videoSettingsPanelControllerProvider =
    VideoSettingsPanelControllerFamily._();

/// Whether a project's video settings are open, and on which item.
///
/// A provider rather than widget state because two separate parts of the
/// screen answer to it: the transport row, which hides its buttons, and the
/// body, which shows the panel. It also remembers the last item for as long
/// as the project is open, so reopening the panel lands where it was left.
final class VideoSettingsPanelControllerProvider
    extends
        $NotifierProvider<
          VideoSettingsPanelController,
          VideoSettingsPanelState
        > {
  /// Whether a project's video settings are open, and on which item.
  ///
  /// A provider rather than widget state because two separate parts of the
  /// screen answer to it: the transport row, which hides its buttons, and the
  /// body, which shows the panel. It also remembers the last item for as long
  /// as the project is open, so reopening the panel lands where it was left.
  VideoSettingsPanelControllerProvider._({
    required VideoSettingsPanelControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'videoSettingsPanelControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$videoSettingsPanelControllerHash();

  @override
  String toString() {
    return r'videoSettingsPanelControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  VideoSettingsPanelController create() => VideoSettingsPanelController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VideoSettingsPanelState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VideoSettingsPanelState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is VideoSettingsPanelControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$videoSettingsPanelControllerHash() =>
    r'cf644d0fb922b84ae9a5d1ecc522d93efb5cd6a0';

/// Whether a project's video settings are open, and on which item.
///
/// A provider rather than widget state because two separate parts of the
/// screen answer to it: the transport row, which hides its buttons, and the
/// body, which shows the panel. It also remembers the last item for as long
/// as the project is open, so reopening the panel lands where it was left.

final class VideoSettingsPanelControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          VideoSettingsPanelController,
          VideoSettingsPanelState,
          VideoSettingsPanelState,
          VideoSettingsPanelState,
          String
        > {
  VideoSettingsPanelControllerFamily._()
    : super(
        retry: null,
        name: r'videoSettingsPanelControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Whether a project's video settings are open, and on which item.
  ///
  /// A provider rather than widget state because two separate parts of the
  /// screen answer to it: the transport row, which hides its buttons, and the
  /// body, which shows the panel. It also remembers the last item for as long
  /// as the project is open, so reopening the panel lands where it was left.

  VideoSettingsPanelControllerProvider call(String projectId) =>
      VideoSettingsPanelControllerProvider._(argument: projectId, from: this);

  @override
  String toString() => r'videoSettingsPanelControllerProvider';
}

/// Whether a project's video settings are open, and on which item.
///
/// A provider rather than widget state because two separate parts of the
/// screen answer to it: the transport row, which hides its buttons, and the
/// body, which shows the panel. It also remembers the last item for as long
/// as the project is open, so reopening the panel lands where it was left.

abstract class _$VideoSettingsPanelController
    extends $Notifier<VideoSettingsPanelState> {
  late final _$args = ref.$arg as String;
  String get projectId => _$args;

  VideoSettingsPanelState build(String projectId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<VideoSettingsPanelState, VideoSettingsPanelState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<VideoSettingsPanelState, VideoSettingsPanelState>,
              VideoSettingsPanelState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
