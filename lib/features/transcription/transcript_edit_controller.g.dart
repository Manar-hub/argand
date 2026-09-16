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

/// Which speaker a tap assigns while [TranscriptEditScope.speakers] is active.
///
/// Defaults to speaker 0 rather than to nothing: a palette with no selection
/// makes the first tap do nothing, which reads as the control being broken.

@ProviderFor(SelectedSpeaker)
final selectedSpeakerProvider = SelectedSpeakerProvider._();

/// Which speaker a tap assigns while [TranscriptEditScope.speakers] is active.
///
/// Defaults to speaker 0 rather than to nothing: a palette with no selection
/// makes the first tap do nothing, which reads as the control being broken.
final class SelectedSpeakerProvider
    extends $NotifierProvider<SelectedSpeaker, int> {
  /// Which speaker a tap assigns while [TranscriptEditScope.speakers] is active.
  ///
  /// Defaults to speaker 0 rather than to nothing: a palette with no selection
  /// makes the first tap do nothing, which reads as the control being broken.
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
///
/// Defaults to speaker 0 rather than to nothing: a palette with no selection
/// makes the first tap do nothing, which reads as the control being broken.

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
///
/// Null when no range is in progress. Two taps rather than a drag because the
/// transcript scrolls vertically and a paint stroke would fight the scroll
/// gesture — so this holds the state between them.
///
/// **Must be cleared when the mode changes.** A pending anchor that outlived
/// Speakers scope would silently turn a later, unrelated tap into a range
/// assignment; `project_screen.dart` clears it on leaving the scope and on
/// leaving edit mode.

@ProviderFor(SpeakerRangeAnchor)
final speakerRangeAnchorProvider = SpeakerRangeAnchorProvider._();

/// The first word of a range being picked, as a `Words.position`.
///
/// Null when no range is in progress. Two taps rather than a drag because the
/// transcript scrolls vertically and a paint stroke would fight the scroll
/// gesture — so this holds the state between them.
///
/// **Must be cleared when the mode changes.** A pending anchor that outlived
/// Speakers scope would silently turn a later, unrelated tap into a range
/// assignment; `project_screen.dart` clears it on leaving the scope and on
/// leaving edit mode.
final class SpeakerRangeAnchorProvider
    extends $NotifierProvider<SpeakerRangeAnchor, int?> {
  /// The first word of a range being picked, as a `Words.position`.
  ///
  /// Null when no range is in progress. Two taps rather than a drag because the
  /// transcript scrolls vertically and a paint stroke would fight the scroll
  /// gesture — so this holds the state between them.
  ///
  /// **Must be cleared when the mode changes.** A pending anchor that outlived
  /// Speakers scope would silently turn a later, unrelated tap into a range
  /// assignment; `project_screen.dart` clears it on leaving the scope and on
  /// leaving edit mode.
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
///
/// Null when no range is in progress. Two taps rather than a drag because the
/// transcript scrolls vertically and a paint stroke would fight the scroll
/// gesture — so this holds the state between them.
///
/// **Must be cleared when the mode changes.** A pending anchor that outlived
/// Speakers scope would silently turn a later, unrelated tap into a range
/// assignment; `project_screen.dart` clears it on leaving the scope and on
/// leaving edit mode.

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
///
/// **Replaces a modal dialog**, and the reason is that a dialog is the wrong
/// shape for this on a phone. Retyping a line is a keyboard task, and a
/// keyboard already covers half the screen; putting a second surface in front
/// of the transcript hides the very context the correction is being made
/// against. Inline, the line stays where it is, the words around it stay
/// readable, and the only new thing on screen is the keyboard.
///
/// Positions rather than words, so the target survives the transcript stream
/// re-emitting mid-edit — the rows are rebuilt from the database on every
/// change, and a held `Word` object would be a stale copy.

@ProviderFor(InlineEdit)
final inlineEditProvider = InlineEditProvider._();

/// The span of words currently open for retyping, or null when none is.
///
/// **Replaces a modal dialog**, and the reason is that a dialog is the wrong
/// shape for this on a phone. Retyping a line is a keyboard task, and a
/// keyboard already covers half the screen; putting a second surface in front
/// of the transcript hides the very context the correction is being made
/// against. Inline, the line stays where it is, the words around it stay
/// readable, and the only new thing on screen is the keyboard.
///
/// Positions rather than words, so the target survives the transcript stream
/// re-emitting mid-edit — the rows are rebuilt from the database on every
/// change, and a held `Word` object would be a stale copy.
final class InlineEditProvider
    extends $NotifierProvider<InlineEdit, ({int from, int to})?> {
  /// The span of words currently open for retyping, or null when none is.
  ///
  /// **Replaces a modal dialog**, and the reason is that a dialog is the wrong
  /// shape for this on a phone. Retyping a line is a keyboard task, and a
  /// keyboard already covers half the screen; putting a second surface in front
  /// of the transcript hides the very context the correction is being made
  /// against. Inline, the line stays where it is, the words around it stay
  /// readable, and the only new thing on screen is the keyboard.
  ///
  /// Positions rather than words, so the target survives the transcript stream
  /// re-emitting mid-edit — the rows are rebuilt from the database on every
  /// change, and a held `Word` object would be a stale copy.
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
///
/// **Replaces a modal dialog**, and the reason is that a dialog is the wrong
/// shape for this on a phone. Retyping a line is a keyboard task, and a
/// keyboard already covers half the screen; putting a second surface in front
/// of the transcript hides the very context the correction is being made
/// against. Inline, the line stays where it is, the words around it stay
/// readable, and the only new thing on screen is the keyboard.
///
/// Positions rather than words, so the target survives the transcript stream
/// re-emitting mid-edit — the rows are rebuilt from the database on every
/// change, and a held `Word` object would be a stale copy.

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
