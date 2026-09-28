// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transcript_edit_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Whether the transcript is being read or corrected.

@ProviderFor(TranscriptEditMode)
final transcriptEditModeProvider = TranscriptEditModeProvider._();

/// Whether the transcript is being read or corrected.
final class TranscriptEditModeProvider
    extends $NotifierProvider<TranscriptEditMode, bool> {
  /// Whether the transcript is being read or corrected.
  TranscriptEditModeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'transcriptEditModeProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$transcriptEditModeHash();

  @$internal
  @override
  TranscriptEditMode create() => TranscriptEditMode();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$transcriptEditModeHash() =>
    r'6e349ccdab092e836200266d1b963e5c8b7aa1bf';

/// Whether the transcript is being read or corrected.

abstract class _$TranscriptEditMode extends $Notifier<bool> {
  bool build();
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
    return element.handleCreate(ref, build);
  }
}

/// Whether a tap edits a whole line or a single word.

@ProviderFor(TranscriptEditScopeSetting)
final transcriptEditScopeSettingProvider =
    TranscriptEditScopeSettingProvider._();

/// Whether a tap edits a whole line or a single word.
final class TranscriptEditScopeSettingProvider
    extends $NotifierProvider<TranscriptEditScopeSetting, TranscriptEditScope> {
  /// Whether a tap edits a whole line or a single word.
  TranscriptEditScopeSettingProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'transcriptEditScopeSettingProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$transcriptEditScopeSettingHash();

  @$internal
  @override
  TranscriptEditScopeSetting create() => TranscriptEditScopeSetting();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TranscriptEditScope value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TranscriptEditScope>(value),
    );
  }
}

String _$transcriptEditScopeSettingHash() =>
    r'ea5abcc9ac8b41a94fac9c924cefee08cb379146';

/// Whether a tap edits a whole line or a single word.

abstract class _$TranscriptEditScopeSetting
    extends $Notifier<TranscriptEditScope> {
  TranscriptEditScope build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<TranscriptEditScope, TranscriptEditScope>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<TranscriptEditScope, TranscriptEditScope>,
              TranscriptEditScope,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Which speaker a tap assigns while [TranscriptEditScope.speakers] is active.

@ProviderFor(SelectedSpeaker)
final selectedSpeakerProvider = SelectedSpeakerProvider._();

/// Which speaker a tap assigns while [TranscriptEditScope.speakers] is active.
final class SelectedSpeakerProvider
    extends $NotifierProvider<SelectedSpeaker, int> {
  /// Which speaker a tap assigns while [TranscriptEditScope.speakers] is active.
  SelectedSpeakerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectedSpeakerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectedSpeakerHash();

  @$internal
  @override
  SelectedSpeaker create() => SelectedSpeaker();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$selectedSpeakerHash() => r'a3097d43b4e999a278a109fdd23a146670b5d765';

/// Which speaker a tap assigns while [TranscriptEditScope.speakers] is active.

abstract class _$SelectedSpeaker extends $Notifier<int> {
  int build();
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
    return element.handleCreate(ref, build);
  }
}

/// The first word of a range being picked, as a `Words.position`.

@ProviderFor(SpeakerRangeAnchor)
final speakerRangeAnchorProvider = SpeakerRangeAnchorProvider._();

/// The first word of a range being picked, as a `Words.position`.
final class SpeakerRangeAnchorProvider
    extends $NotifierProvider<SpeakerRangeAnchor, int?> {
  /// The first word of a range being picked, as a `Words.position`.
  SpeakerRangeAnchorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'speakerRangeAnchorProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$speakerRangeAnchorHash();

  @$internal
  @override
  SpeakerRangeAnchor create() => SpeakerRangeAnchor();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int?>(value),
    );
  }
}

String _$speakerRangeAnchorHash() =>
    r'beaf5d16fd63c8a17fb87f88af247a61e6c66b0e';

/// The first word of a range being picked, as a `Words.position`.

abstract class _$SpeakerRangeAnchor extends $Notifier<int?> {
  int? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<int?, int?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<int?, int?>,
              int?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The span of words currently open for retyping, or null when none is.

@ProviderFor(InlineEdit)
final inlineEditProvider = InlineEditProvider._();

/// The span of words currently open for retyping, or null when none is.
final class InlineEditProvider
    extends $NotifierProvider<InlineEdit, ({int from, int to})?> {
  /// The span of words currently open for retyping, or null when none is.
  InlineEditProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'inlineEditProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$inlineEditHash();

  @$internal
  @override
  InlineEdit create() => InlineEdit();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(({int from, int to})? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<({int from, int to})?>(value),
    );
  }
}

String _$inlineEditHash() => r'2be335e9130fd50341f578a4ec875879ef16d5eb';

/// The span of words currently open for retyping, or null when none is.

abstract class _$InlineEdit extends $Notifier<({int from, int to})?> {
  ({int from, int to})? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<({int from, int to})?, ({int from, int to})?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<({int from, int to})?, ({int from, int to})?>,
              ({int from, int to})?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
