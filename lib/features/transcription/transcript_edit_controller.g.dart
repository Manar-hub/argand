// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transcript_edit_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Whether the transcript is being read or corrected.
///
/// **Why a mode rather than a menu on every tap.** In playback a tap on a word
/// means "seek there", which is the transcript's primary gesture and the reason
/// it is worth scrolling. Putting a chooser in front of that would slow down the
/// common action to serve the rare one. A single toggle keeps both intents
/// unambiguous: reading seeks, editing edits.
///
/// It also keeps the layout free of per-line controls. In edit mode the two
/// things already on screen become the two controls — a word edits its text, a
/// speaker label reassigns its turn — so nothing is added to the page.
///
/// Deliberately not persisted. Editing is something you do deliberately and
/// then leave; reopening a project in edit mode would be a surprise, and an
/// accidental tap on a word would rewrite text rather than seek.

@ProviderFor(TranscriptEditMode)
final transcriptEditModeProvider = TranscriptEditModeProvider._();

/// Whether the transcript is being read or corrected.
///
/// **Why a mode rather than a menu on every tap.** In playback a tap on a word
/// means "seek there", which is the transcript's primary gesture and the reason
/// it is worth scrolling. Putting a chooser in front of that would slow down the
/// common action to serve the rare one. A single toggle keeps both intents
/// unambiguous: reading seeks, editing edits.
///
/// It also keeps the layout free of per-line controls. In edit mode the two
/// things already on screen become the two controls — a word edits its text, a
/// speaker label reassigns its turn — so nothing is added to the page.
///
/// Deliberately not persisted. Editing is something you do deliberately and
/// then leave; reopening a project in edit mode would be a surprise, and an
/// accidental tap on a word would rewrite text rather than seek.
final class TranscriptEditModeProvider
    extends $NotifierProvider<TranscriptEditMode, bool> {
  /// Whether the transcript is being read or corrected.
  ///
  /// **Why a mode rather than a menu on every tap.** In playback a tap on a word
  /// means "seek there", which is the transcript's primary gesture and the reason
  /// it is worth scrolling. Putting a chooser in front of that would slow down the
  /// common action to serve the rare one. A single toggle keeps both intents
  /// unambiguous: reading seeks, editing edits.
  ///
  /// It also keeps the layout free of per-line controls. In edit mode the two
  /// things already on screen become the two controls — a word edits its text, a
  /// speaker label reassigns its turn — so nothing is added to the page.
  ///
  /// Deliberately not persisted. Editing is something you do deliberately and
  /// then leave; reopening a project in edit mode would be a surprise, and an
  /// accidental tap on a word would rewrite text rather than seek.
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
///
/// **Why a mode rather than a menu on every tap.** In playback a tap on a word
/// means "seek there", which is the transcript's primary gesture and the reason
/// it is worth scrolling. Putting a chooser in front of that would slow down the
/// common action to serve the rare one. A single toggle keeps both intents
/// unambiguous: reading seeks, editing edits.
///
/// It also keeps the layout free of per-line controls. In edit mode the two
/// things already on screen become the two controls — a word edits its text, a
/// speaker label reassigns its turn — so nothing is added to the page.
///
/// Deliberately not persisted. Editing is something you do deliberately and
/// then leave; reopening a project in edit mode would be a surprise, and an
/// accidental tap on a word would rewrite text rather than seek.

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
///
/// Defaults to [TranscriptEditScope.line] because the common correction is a
/// phrase — "brainbeats" for "praying beads" spans a word boundary and cannot
/// be typed one word at a time. Word is the deliberate choice for when the
/// timing matters more than the convenience.
///
/// Not persisted, for the same reason [TranscriptEditMode] is not: it is picked
/// for a task, and inheriting it on a later launch would surprise.

@ProviderFor(TranscriptEditScopeSetting)
final transcriptEditScopeSettingProvider =
    TranscriptEditScopeSettingProvider._();

/// Whether a tap edits a whole line or a single word.
///
/// Defaults to [TranscriptEditScope.line] because the common correction is a
/// phrase — "brainbeats" for "praying beads" spans a word boundary and cannot
/// be typed one word at a time. Word is the deliberate choice for when the
/// timing matters more than the convenience.
///
/// Not persisted, for the same reason [TranscriptEditMode] is not: it is picked
/// for a task, and inheriting it on a later launch would surprise.
final class TranscriptEditScopeSettingProvider
    extends $NotifierProvider<TranscriptEditScopeSetting, TranscriptEditScope> {
  /// Whether a tap edits a whole line or a single word.
  ///
  /// Defaults to [TranscriptEditScope.line] because the common correction is a
  /// phrase — "brainbeats" for "praying beads" spans a word boundary and cannot
  /// be typed one word at a time. Word is the deliberate choice for when the
  /// timing matters more than the convenience.
  ///
  /// Not persisted, for the same reason [TranscriptEditMode] is not: it is picked
  /// for a task, and inheriting it on a later launch would surprise.
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
///
/// Defaults to [TranscriptEditScope.line] because the common correction is a
/// phrase — "brainbeats" for "praying beads" spans a word boundary and cannot
/// be typed one word at a time. Word is the deliberate choice for when the
/// timing matters more than the convenience.
///
/// Not persisted, for the same reason [TranscriptEditMode] is not: it is picked
/// for a task, and inheriting it on a later launch would surprise.

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
