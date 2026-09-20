// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'clip_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Which clip the timeline and Script mode are currently showing.
///
/// **One selection per project**, held in memory rather than persisted: it is a
/// cursor, not a preference, and restoring yesterday's selection would be
/// arbitrary once clips have been added or removed since.
///
/// Null means nothing is selected — an empty project, or the moment after the
/// selected clip was removed. The timeline resolves null to the first clip when
/// one exists, which is why this stays deliberately dumb.

@ProviderFor(SelectedClip)
final selectedClipProvider = SelectedClipFamily._();

/// Which clip the timeline and Script mode are currently showing.
///
/// **One selection per project**, held in memory rather than persisted: it is a
/// cursor, not a preference, and restoring yesterday's selection would be
/// arbitrary once clips have been added or removed since.
///
/// Null means nothing is selected — an empty project, or the moment after the
/// selected clip was removed. The timeline resolves null to the first clip when
/// one exists, which is why this stays deliberately dumb.
final class SelectedClipProvider
    extends $NotifierProvider<SelectedClip, String?> {
  /// Which clip the timeline and Script mode are currently showing.
  ///
  /// **One selection per project**, held in memory rather than persisted: it is a
  /// cursor, not a preference, and restoring yesterday's selection would be
  /// arbitrary once clips have been added or removed since.
  ///
  /// Null means nothing is selected — an empty project, or the moment after the
  /// selected clip was removed. The timeline resolves null to the first clip when
  /// one exists, which is why this stays deliberately dumb.
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
///
/// **One selection per project**, held in memory rather than persisted: it is a
/// cursor, not a preference, and restoring yesterday's selection would be
/// arbitrary once clips have been added or removed since.
///
/// Null means nothing is selected — an empty project, or the moment after the
/// selected clip was removed. The timeline resolves null to the first clip when
/// one exists, which is why this stays deliberately dumb.

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
  ///
  /// **One selection per project**, held in memory rather than persisted: it is a
  /// cursor, not a preference, and restoring yesterday's selection would be
  /// arbitrary once clips have been added or removed since.
  ///
  /// Null means nothing is selected — an empty project, or the moment after the
  /// selected clip was removed. The timeline resolves null to the first clip when
  /// one exists, which is why this stays deliberately dumb.

  SelectedClipProvider call(String projectId) =>
      SelectedClipProvider._(argument: projectId, from: this);

  @override
  String toString() => r'selectedClipProvider';
}

/// Which clip the timeline and Script mode are currently showing.
///
/// **One selection per project**, held in memory rather than persisted: it is a
/// cursor, not a preference, and restoring yesterday's selection would be
/// arbitrary once clips have been added or removed since.
///
/// Null means nothing is selected — an empty project, or the moment after the
/// selected clip was removed. The timeline resolves null to the first clip when
/// one exists, which is why this stays deliberately dumb.

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

/// Which clip both modes are actually showing.
///
/// [SelectedClip] holds what the user last tapped; this resolves it against
/// the clips that currently exist. Shared so Timeline and Script cannot
/// disagree about which clip is in front of the user — they are two views of
/// one selection, and a project whose filmstrip highlights one clip while the
/// transcript shows another would be incoherent.
///
/// Falls back to the first clip rather than to nothing, which is what keeps the
/// screen sensible after a removal: the selected clip can disappear from under
/// the user, and an empty view beside a full timeline would read as a bug.
/// Null only when the project genuinely has no clips.

@ProviderFor(resolvedSelectedClip)
final resolvedSelectedClipProvider = ResolvedSelectedClipFamily._();

/// Which clip both modes are actually showing.
///
/// [SelectedClip] holds what the user last tapped; this resolves it against
/// the clips that currently exist. Shared so Timeline and Script cannot
/// disagree about which clip is in front of the user — they are two views of
/// one selection, and a project whose filmstrip highlights one clip while the
/// transcript shows another would be incoherent.
///
/// Falls back to the first clip rather than to nothing, which is what keeps the
/// screen sensible after a removal: the selected clip can disappear from under
/// the user, and an empty view beside a full timeline would read as a bug.
/// Null only when the project genuinely has no clips.

final class ResolvedSelectedClipProvider
    extends $FunctionalProvider<String?, String?, String?>
    with $Provider<String?> {
  /// Which clip both modes are actually showing.
  ///
  /// [SelectedClip] holds what the user last tapped; this resolves it against
  /// the clips that currently exist. Shared so Timeline and Script cannot
  /// disagree about which clip is in front of the user — they are two views of
  /// one selection, and a project whose filmstrip highlights one clip while the
  /// transcript shows another would be incoherent.
  ///
  /// Falls back to the first clip rather than to nothing, which is what keeps the
  /// screen sensible after a removal: the selected clip can disappear from under
  /// the user, and an empty view beside a full timeline would read as a bug.
  /// Null only when the project genuinely has no clips.
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
///
/// [SelectedClip] holds what the user last tapped; this resolves it against
/// the clips that currently exist. Shared so Timeline and Script cannot
/// disagree about which clip is in front of the user — they are two views of
/// one selection, and a project whose filmstrip highlights one clip while the
/// transcript shows another would be incoherent.
///
/// Falls back to the first clip rather than to nothing, which is what keeps the
/// screen sensible after a removal: the selected clip can disappear from under
/// the user, and an empty view beside a full timeline would read as a bug.
/// Null only when the project genuinely has no clips.

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
  ///
  /// [SelectedClip] holds what the user last tapped; this resolves it against
  /// the clips that currently exist. Shared so Timeline and Script cannot
  /// disagree about which clip is in front of the user — they are two views of
  /// one selection, and a project whose filmstrip highlights one clip while the
  /// transcript shows another would be incoherent.
  ///
  /// Falls back to the first clip rather than to nothing, which is what keeps the
  /// screen sensible after a removal: the selected clip can disappear from under
  /// the user, and an empty view beside a full timeline would read as a bug.
  /// Null only when the project genuinely has no clips.

  ResolvedSelectedClipProvider call(String projectId) =>
      ResolvedSelectedClipProvider._(argument: projectId, from: this);

  @override
  String toString() => r'resolvedSelectedClipProvider';
}

/// Adds media to a project without transcribing it.
///
/// **This is the half of import that does not run the engine.** Picking a file
/// used to mean committing to minutes of whisper and diarization; a project
/// that holds several clips cannot work that way, because most of them are not
/// worth that cost until the user says so. So this copies the bytes in, probes
/// the duration and writes a row — seconds, not minutes — and transcription is
/// a separate, explicit act: drawing a transcribe layer and running it.

@ProviderFor(AddClipController)
final addClipControllerProvider = AddClipControllerFamily._();

/// Adds media to a project without transcribing it.
///
/// **This is the half of import that does not run the engine.** Picking a file
/// used to mean committing to minutes of whisper and diarization; a project
/// that holds several clips cannot work that way, because most of them are not
/// worth that cost until the user says so. So this copies the bytes in, probes
/// the duration and writes a row — seconds, not minutes — and transcription is
/// a separate, explicit act: drawing a transcribe layer and running it.
final class AddClipControllerProvider
    extends $NotifierProvider<AddClipController, AddClipStatus> {
  /// Adds media to a project without transcribing it.
  ///
  /// **This is the half of import that does not run the engine.** Picking a file
  /// used to mean committing to minutes of whisper and diarization; a project
  /// that holds several clips cannot work that way, because most of them are not
  /// worth that cost until the user says so. So this copies the bytes in, probes
  /// the duration and writes a row — seconds, not minutes — and transcription is
  /// a separate, explicit act: drawing a transcribe layer and running it.
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
///
/// **This is the half of import that does not run the engine.** Picking a file
/// used to mean committing to minutes of whisper and diarization; a project
/// that holds several clips cannot work that way, because most of them are not
/// worth that cost until the user says so. So this copies the bytes in, probes
/// the duration and writes a row — seconds, not minutes — and transcription is
/// a separate, explicit act: drawing a transcribe layer and running it.

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
  ///
  /// **This is the half of import that does not run the engine.** Picking a file
  /// used to mean committing to minutes of whisper and diarization; a project
  /// that holds several clips cannot work that way, because most of them are not
  /// worth that cost until the user says so. So this copies the bytes in, probes
  /// the duration and writes a row — seconds, not minutes — and transcription is
  /// a separate, explicit act: drawing a transcribe layer and running it.

  AddClipControllerProvider call(String projectId) =>
      AddClipControllerProvider._(argument: projectId, from: this);

  @override
  String toString() => r'addClipControllerProvider';
}

/// Adds media to a project without transcribing it.
///
/// **This is the half of import that does not run the engine.** Picking a file
/// used to mean committing to minutes of whisper and diarization; a project
/// that holds several clips cannot work that way, because most of them are not
/// worth that cost until the user says so. So this copies the bytes in, probes
/// the duration and writes a row — seconds, not minutes — and transcription is
/// a separate, explicit act: drawing a transcribe layer and running it.

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
///
/// Separate from [AddClipController] because these need no status of their own:
/// both are immediate, both are driven straight off the clip stream, and
/// neither has a stage worth rendering.

@ProviderFor(clipEditor)
final clipEditorProvider = ClipEditorProvider._();

/// Removing and reordering clips.
///
/// Separate from [AddClipController] because these need no status of their own:
/// both are immediate, both are driven straight off the clip stream, and
/// neither has a stage worth rendering.

final class ClipEditorProvider
    extends $FunctionalProvider<ClipEditor, ClipEditor, ClipEditor>
    with $Provider<ClipEditor> {
  /// Removing and reordering clips.
  ///
  /// Separate from [AddClipController] because these need no status of their own:
  /// both are immediate, both are driven straight off the clip stream, and
  /// neither has a stage worth rendering.
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
