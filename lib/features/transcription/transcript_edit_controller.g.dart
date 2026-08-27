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
