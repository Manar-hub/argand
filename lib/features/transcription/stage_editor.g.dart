// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stage_editor.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Placements being changed right now, before they are saved.

@ProviderFor(StageLive)
final stageLiveProvider = StageLiveFamily._();

/// Placements being changed right now, before they are saved.
final class StageLiveProvider
    extends $NotifierProvider<StageLive, Map<TimelineItem, ItemTransform>> {
  /// Placements being changed right now, before they are saved.
  StageLiveProvider._({
    required StageLiveFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'stageLiveProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$stageLiveHash();

  @override
  String toString() {
    return r'stageLiveProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  StageLive create() => StageLive();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<TimelineItem, ItemTransform> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<TimelineItem, ItemTransform>>(
        value,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is StageLiveProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$stageLiveHash() => r'7cd0020cd6ee38391671799b4e649d6acd5b3635';

/// Placements being changed right now, before they are saved.

final class StageLiveFamily extends $Family
    with
        $ClassFamilyOverride<
          StageLive,
          Map<TimelineItem, ItemTransform>,
          Map<TimelineItem, ItemTransform>,
          Map<TimelineItem, ItemTransform>,
          String
        > {
  StageLiveFamily._()
    : super(
        retry: null,
        name: r'stageLiveProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Placements being changed right now, before they are saved.

  StageLiveProvider call(String projectId) =>
      StageLiveProvider._(argument: projectId, from: this);

  @override
  String toString() => r'stageLiveProvider';
}

/// Placements being changed right now, before they are saved.

abstract class _$StageLive extends $Notifier<Map<TimelineItem, ItemTransform>> {
  late final _$args = ref.$arg as String;
  String get projectId => _$args;

  Map<TimelineItem, ItemTransform> build(String projectId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              Map<TimelineItem, ItemTransform>,
              Map<TimelineItem, ItemTransform>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                Map<TimelineItem, ItemTransform>,
                Map<TimelineItem, ItemTransform>
              >,
              Map<TimelineItem, ItemTransform>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Which item on the stage is having its words typed, if any.

@ProviderFor(StageEditing)
final stageEditingProvider = StageEditingFamily._();

/// Which item on the stage is having its words typed, if any.
final class StageEditingProvider
    extends $NotifierProvider<StageEditing, TimelineItem?> {
  /// Which item on the stage is having its words typed, if any.
  StageEditingProvider._({
    required StageEditingFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'stageEditingProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$stageEditingHash();

  @override
  String toString() {
    return r'stageEditingProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  StageEditing create() => StageEditing();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TimelineItem? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TimelineItem?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is StageEditingProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$stageEditingHash() => r'96bf77f70a2e0fea6725f6ba5b50d63c8567dca8';

/// Which item on the stage is having its words typed, if any.

final class StageEditingFamily extends $Family
    with
        $ClassFamilyOverride<
          StageEditing,
          TimelineItem?,
          TimelineItem?,
          TimelineItem?,
          String
        > {
  StageEditingFamily._()
    : super(
        retry: null,
        name: r'stageEditingProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Which item on the stage is having its words typed, if any.

  StageEditingProvider call(String projectId) =>
      StageEditingProvider._(argument: projectId, from: this);

  @override
  String toString() => r'stageEditingProvider';
}

/// Which item on the stage is having its words typed, if any.

abstract class _$StageEditing extends $Notifier<TimelineItem?> {
  late final _$args = ref.$arg as String;
  String get projectId => _$args;

  TimelineItem? build(String projectId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<TimelineItem?, TimelineItem?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<TimelineItem?, TimelineItem?>,
              TimelineItem?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
