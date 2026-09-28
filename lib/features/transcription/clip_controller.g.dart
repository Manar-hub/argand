// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'clip_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Which clip the timeline and Script mode are currently showing.

@ProviderFor(SelectedClip)
final selectedClipProvider = SelectedClipFamily._();

/// Which clip the timeline and Script mode are currently showing.
final class SelectedClipProvider
    extends $NotifierProvider<SelectedClip, String?> {
  /// Which clip the timeline and Script mode are currently showing.
  SelectedClipProvider._({
    required SelectedClipFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'selectedClipProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$selectedClipHash();

  @override
  String toString() {
    return r'selectedClipProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  SelectedClip create() => SelectedClip();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SelectedClipProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$selectedClipHash() => r'95299c294ac52dcb478bbcb4fd9f371a31659c1e';

/// Which clip the timeline and Script mode are currently showing.

final class SelectedClipFamily extends $Family
    with $ClassFamilyOverride<SelectedClip, String?, String?, String?, String> {
  SelectedClipFamily._()
    : super(
        retry: null,
        name: r'selectedClipProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Which clip the timeline and Script mode are currently showing.

  SelectedClipProvider call(String projectId) =>
      SelectedClipProvider._(argument: projectId, from: this);

  @override
  String toString() => r'selectedClipProvider';
}

/// Which clip the timeline and Script mode are currently showing.

abstract class _$SelectedClip extends $Notifier<String?> {
  late final _$args = ref.$arg as String;
  String get projectId => _$args;

  String? build(String projectId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<String?, String?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String?, String?>,
              String?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Which tracks the eye in the gutter has hidden, by `Tracks` row id.

@ProviderFor(HiddenTracks)
final hiddenTracksProvider = HiddenTracksFamily._();

/// Which tracks the eye in the gutter has hidden, by `Tracks` row id.
final class HiddenTracksProvider
    extends $NotifierProvider<HiddenTracks, Set<String>> {
  /// Which tracks the eye in the gutter has hidden, by `Tracks` row id.
  HiddenTracksProvider._({
    required HiddenTracksFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'hiddenTracksProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$hiddenTracksHash();

  @override
  String toString() {
    return r'hiddenTracksProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  HiddenTracks create() => HiddenTracks();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Set<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Set<String>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is HiddenTracksProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$hiddenTracksHash() => r'2ab9f64bb40ac5ac5dbbf2ea334c18cc9c03fcaa';

/// Which tracks the eye in the gutter has hidden, by `Tracks` row id.

final class HiddenTracksFamily extends $Family
    with
        $ClassFamilyOverride<
          HiddenTracks,
          Set<String>,
          Set<String>,
          Set<String>,
          String
        > {
  HiddenTracksFamily._()
    : super(
        retry: null,
        name: r'hiddenTracksProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Which tracks the eye in the gutter has hidden, by `Tracks` row id.

  HiddenTracksProvider call(String projectId) =>
      HiddenTracksProvider._(argument: projectId, from: this);

  @override
  String toString() => r'hiddenTracksProvider';
}

/// Which tracks the eye in the gutter has hidden, by `Tracks` row id.

abstract class _$HiddenTracks extends $Notifier<Set<String>> {
  late final _$args = ref.$arg as String;
  String get projectId => _$args;

  Set<String> build(String projectId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<Set<String>, Set<String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Set<String>, Set<String>>,
              Set<String>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

@ProviderFor(hiddenPlayback)
final hiddenPlaybackProvider = HiddenPlaybackFamily._();

final class HiddenPlaybackProvider
    extends $FunctionalProvider<HiddenPlayback, HiddenPlayback, HiddenPlayback>
    with $Provider<HiddenPlayback> {
  HiddenPlaybackProvider._({
    required HiddenPlaybackFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'hiddenPlaybackProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$hiddenPlaybackHash();

  @override
  String toString() {
    return r'hiddenPlaybackProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<HiddenPlayback> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  HiddenPlayback create(Ref ref) {
    final argument = this.argument as String;
    return hiddenPlayback(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(HiddenPlayback value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<HiddenPlayback>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is HiddenPlaybackProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$hiddenPlaybackHash() => r'd533c66e0e46ed976ccbffc511c1623e22b60641';

final class HiddenPlaybackFamily extends $Family
    with $FunctionalFamilyOverride<HiddenPlayback, String> {
  HiddenPlaybackFamily._()
    : super(
        retry: null,
        name: r'hiddenPlaybackProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  HiddenPlaybackProvider call(String projectId) =>
      HiddenPlaybackProvider._(argument: projectId, from: this);

  @override
  String toString() => r'hiddenPlaybackProvider';
}

/// Where the playhead sits, in project time.

@ProviderFor(TimelinePlayhead)
final timelinePlayheadProvider = TimelinePlayheadFamily._();

/// Where the playhead sits, in project time.
final class TimelinePlayheadProvider
    extends $NotifierProvider<TimelinePlayhead, int> {
  /// Where the playhead sits, in project time.
  TimelinePlayheadProvider._({
    required TimelinePlayheadFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'timelinePlayheadProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$timelinePlayheadHash();

  @override
  String toString() {
    return r'timelinePlayheadProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  TimelinePlayhead create() => TimelinePlayhead();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TimelinePlayheadProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$timelinePlayheadHash() => r'e0cc26a8091fcccd6002cbc7086d27a80279d388';

/// Where the playhead sits, in project time.

final class TimelinePlayheadFamily extends $Family
    with $ClassFamilyOverride<TimelinePlayhead, int, int, int, String> {
  TimelinePlayheadFamily._()
    : super(
        retry: null,
        name: r'timelinePlayheadProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Where the playhead sits, in project time.

  TimelinePlayheadProvider call(String projectId) =>
      TimelinePlayheadProvider._(argument: projectId, from: this);

  @override
  String toString() => r'timelinePlayheadProvider';
}

/// Where the playhead sits, in project time.

abstract class _$TimelinePlayhead extends $Notifier<int> {
  late final _$args = ref.$arg as String;
  String get projectId => _$args;

  int build(String projectId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<int, int>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<int, int>,
              int,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Everything the editing tools will act on.

@ProviderFor(TimelineSelection)
final timelineSelectionProvider = TimelineSelectionFamily._();

/// Everything the editing tools will act on.
final class TimelineSelectionProvider
    extends $NotifierProvider<TimelineSelection, Set<TimelineItem>> {
  /// Everything the editing tools will act on.
  TimelineSelectionProvider._({
    required TimelineSelectionFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'timelineSelectionProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$timelineSelectionHash();

  @override
  String toString() {
    return r'timelineSelectionProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  TimelineSelection create() => TimelineSelection();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Set<TimelineItem> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Set<TimelineItem>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TimelineSelectionProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$timelineSelectionHash() => r'e047ec1b14cdeeaadc880dd78e78d372d9d1d993';

/// Everything the editing tools will act on.

final class TimelineSelectionFamily extends $Family
    with
        $ClassFamilyOverride<
          TimelineSelection,
          Set<TimelineItem>,
          Set<TimelineItem>,
          Set<TimelineItem>,
          String
        > {
  TimelineSelectionFamily._()
    : super(
        retry: null,
        name: r'timelineSelectionProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Everything the editing tools will act on.

  TimelineSelectionProvider call(String projectId) =>
      TimelineSelectionProvider._(argument: projectId, from: this);

  @override
  String toString() => r'timelineSelectionProvider';
}

/// Everything the editing tools will act on.

abstract class _$TimelineSelection extends $Notifier<Set<TimelineItem>> {
  late final _$args = ref.$arg as String;
  String get projectId => _$args;

  Set<TimelineItem> build(String projectId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<Set<TimelineItem>, Set<TimelineItem>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Set<TimelineItem>, Set<TimelineItem>>,
              Set<TimelineItem>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Whether taps on the timeline add to the selection rather than replace it.

@ProviderFor(TimelineMultiSelect)
final timelineMultiSelectProvider = TimelineMultiSelectFamily._();

/// Whether taps on the timeline add to the selection rather than replace it.
final class TimelineMultiSelectProvider
    extends $NotifierProvider<TimelineMultiSelect, bool> {
  /// Whether taps on the timeline add to the selection rather than replace it.
  TimelineMultiSelectProvider._({
    required TimelineMultiSelectFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'timelineMultiSelectProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$timelineMultiSelectHash();

  @override
  String toString() {
    return r'timelineMultiSelectProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  TimelineMultiSelect create() => TimelineMultiSelect();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TimelineMultiSelectProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$timelineMultiSelectHash() =>
    r'313dd76af9271a5a2d76527fb601b0066d595f2e';

/// Whether taps on the timeline add to the selection rather than replace it.

final class TimelineMultiSelectFamily extends $Family
    with $ClassFamilyOverride<TimelineMultiSelect, bool, bool, bool, String> {
  TimelineMultiSelectFamily._()
    : super(
        retry: null,
        name: r'timelineMultiSelectProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Whether taps on the timeline add to the selection rather than replace it.

  TimelineMultiSelectProvider call(String projectId) =>
      TimelineMultiSelectProvider._(argument: projectId, from: this);

  @override
  String toString() => r'timelineMultiSelectProvider';
}

/// Whether taps on the timeline add to the selection rather than replace it.

abstract class _$TimelineMultiSelect extends $Notifier<bool> {
  late final _$args = ref.$arg as String;
  String get projectId => _$args;

  bool build(String projectId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Which clip both modes are actually showing.

@ProviderFor(resolvedSelectedClip)
final resolvedSelectedClipProvider = ResolvedSelectedClipFamily._();

/// Which clip both modes are actually showing.

final class ResolvedSelectedClipProvider
    extends $FunctionalProvider<String?, String?, String?>
    with $Provider<String?> {
  /// Which clip both modes are actually showing.
  ResolvedSelectedClipProvider._({
    required ResolvedSelectedClipFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'resolvedSelectedClipProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$resolvedSelectedClipHash();

  @override
  String toString() {
    return r'resolvedSelectedClipProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<String?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  String? create(Ref ref) {
    final argument = this.argument as String;
    return resolvedSelectedClip(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ResolvedSelectedClipProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$resolvedSelectedClipHash() =>
    r'e50df931bd84987458f7e3f01c91df7487122822';

/// Which clip both modes are actually showing.

final class ResolvedSelectedClipFamily extends $Family
    with $FunctionalFamilyOverride<String?, String> {
  ResolvedSelectedClipFamily._()
    : super(
        retry: null,
        name: r'resolvedSelectedClipProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Which clip both modes are actually showing.

  ResolvedSelectedClipProvider call(String projectId) =>
      ResolvedSelectedClipProvider._(argument: projectId, from: this);

  @override
  String toString() => r'resolvedSelectedClipProvider';
}

/// Adds media to a project without transcribing it.

@ProviderFor(AddClipController)
final addClipControllerProvider = AddClipControllerFamily._();

/// Adds media to a project without transcribing it.
final class AddClipControllerProvider
    extends $NotifierProvider<AddClipController, AddClipStatus> {
  /// Adds media to a project without transcribing it.
  AddClipControllerProvider._({
    required AddClipControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'addClipControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$addClipControllerHash();

  @override
  String toString() {
    return r'addClipControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  AddClipController create() => AddClipController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AddClipStatus value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AddClipStatus>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AddClipControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$addClipControllerHash() => r'c1cc51ffa83d162a63eb56ab68eb3a48c6b49bcf';

/// Adds media to a project without transcribing it.

final class AddClipControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          AddClipController,
          AddClipStatus,
          AddClipStatus,
          AddClipStatus,
          String
        > {
  AddClipControllerFamily._()
    : super(
        retry: null,
        name: r'addClipControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Adds media to a project without transcribing it.

  AddClipControllerProvider call(String projectId) =>
      AddClipControllerProvider._(argument: projectId, from: this);

  @override
  String toString() => r'addClipControllerProvider';
}

/// Adds media to a project without transcribing it.

abstract class _$AddClipController extends $Notifier<AddClipStatus> {
  late final _$args = ref.$arg as String;
  String get projectId => _$args;

  AddClipStatus build(String projectId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AddClipStatus, AddClipStatus>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AddClipStatus, AddClipStatus>,
              AddClipStatus,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Removing and reordering clips.

@ProviderFor(clipEditor)
final clipEditorProvider = ClipEditorProvider._();

/// Removing and reordering clips.

final class ClipEditorProvider
    extends $FunctionalProvider<ClipEditor, ClipEditor, ClipEditor>
    with $Provider<ClipEditor> {
  /// Removing and reordering clips.
  ClipEditorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'clipEditorProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$clipEditorHash();

  @$internal
  @override
  $ProviderElement<ClipEditor> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ClipEditor create(Ref ref) {
    return clipEditor(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ClipEditor value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ClipEditor>(value),
    );
  }
}

String _$clipEditorHash() => r'bc80f7a8e100f7b8477127ec7471d4456cda440a';

/// Total bytes one clip occupies, for the remove confirmation.

@ProviderFor(clipMediaBytes)
final clipMediaBytesProvider = ClipMediaBytesFamily._();

/// Total bytes one clip occupies, for the remove confirmation.

final class ClipMediaBytesProvider
    extends $FunctionalProvider<AsyncValue<int>, int, FutureOr<int>>
    with $FutureModifier<int>, $FutureProvider<int> {
  /// Total bytes one clip occupies, for the remove confirmation.
  ClipMediaBytesProvider._({
    required ClipMediaBytesFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'clipMediaBytesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$clipMediaBytesHash();

  @override
  String toString() {
    return r'clipMediaBytesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<int> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<int> create(Ref ref) {
    final argument = this.argument as String;
    return clipMediaBytes(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ClipMediaBytesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$clipMediaBytesHash() => r'8ae607bc4d24756962ee71bcc92fc13d8cc9f98d';

/// Total bytes one clip occupies, for the remove confirmation.

final class ClipMediaBytesFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<int>, String> {
  ClipMediaBytesFamily._()
    : super(
        retry: null,
        name: r'clipMediaBytesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Total bytes one clip occupies, for the remove confirmation.

  ClipMediaBytesProvider call(String projectId) =>
      ClipMediaBytesProvider._(argument: projectId, from: this);

  @override
  String toString() => r'clipMediaBytesProvider';
}
