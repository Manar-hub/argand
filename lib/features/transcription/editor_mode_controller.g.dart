// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'editor_mode_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Which mode [projectId]'s editing screen is currently showing.
///
/// Starts at [EditorMode.script] -- the least surprising default, and the
/// only mode every project opened in before Timeline mode existed.
/// `ProjectScreen` overrides this once, in `initState`, either from the entry
/// point that was tapped (import-and-edit vs. transcribe) or, for a project
/// reopened from the library list, from whichever mode was last recorded for
/// it via [select].

@ProviderFor(SessionEditorMode)
final sessionEditorModeProvider = SessionEditorModeFamily._();

/// Which mode [projectId]'s editing screen is currently showing.
///
/// Starts at [EditorMode.script] -- the least surprising default, and the
/// only mode every project opened in before Timeline mode existed.
/// `ProjectScreen` overrides this once, in `initState`, either from the entry
/// point that was tapped (import-and-edit vs. transcribe) or, for a project
/// reopened from the library list, from whichever mode was last recorded for
/// it via [select].
final class SessionEditorModeProvider
    extends $NotifierProvider<SessionEditorMode, EditorMode> {
  /// Which mode [projectId]'s editing screen is currently showing.
  ///
  /// Starts at [EditorMode.script] -- the least surprising default, and the
  /// only mode every project opened in before Timeline mode existed.
  /// `ProjectScreen` overrides this once, in `initState`, either from the entry
  /// point that was tapped (import-and-edit vs. transcribe) or, for a project
  /// reopened from the library list, from whichever mode was last recorded for
  /// it via [select].
  SessionEditorModeProvider._({
    required SessionEditorModeFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'sessionEditorModeProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$sessionEditorModeHash();

  @override
  String toString() {
    return r'sessionEditorModeProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  SessionEditorMode create() => SessionEditorMode();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(EditorMode value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<EditorMode>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SessionEditorModeProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$sessionEditorModeHash() => r'20dfeea1d7290af808bb6bc398938e9267ae600f';

/// Which mode [projectId]'s editing screen is currently showing.
///
/// Starts at [EditorMode.script] -- the least surprising default, and the
/// only mode every project opened in before Timeline mode existed.
/// `ProjectScreen` overrides this once, in `initState`, either from the entry
/// point that was tapped (import-and-edit vs. transcribe) or, for a project
/// reopened from the library list, from whichever mode was last recorded for
/// it via [select].

final class SessionEditorModeFamily extends $Family
    with
        $ClassFamilyOverride<
          SessionEditorMode,
          EditorMode,
          EditorMode,
          EditorMode,
          String
        > {
  SessionEditorModeFamily._()
    : super(
        retry: null,
        name: r'sessionEditorModeProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Which mode [projectId]'s editing screen is currently showing.
  ///
  /// Starts at [EditorMode.script] -- the least surprising default, and the
  /// only mode every project opened in before Timeline mode existed.
  /// `ProjectScreen` overrides this once, in `initState`, either from the entry
  /// point that was tapped (import-and-edit vs. transcribe) or, for a project
  /// reopened from the library list, from whichever mode was last recorded for
  /// it via [select].

  SessionEditorModeProvider call(String projectId) =>
      SessionEditorModeProvider._(argument: projectId, from: this);

  @override
  String toString() => r'sessionEditorModeProvider';
}

/// Which mode [projectId]'s editing screen is currently showing.
///
/// Starts at [EditorMode.script] -- the least surprising default, and the
/// only mode every project opened in before Timeline mode existed.
/// `ProjectScreen` overrides this once, in `initState`, either from the entry
/// point that was tapped (import-and-edit vs. transcribe) or, for a project
/// reopened from the library list, from whichever mode was last recorded for
/// it via [select].

abstract class _$SessionEditorMode extends $Notifier<EditorMode> {
  late final _$args = ref.$arg as String;
  String get projectId => _$args;

  EditorMode build(String projectId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<EditorMode, EditorMode>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<EditorMode, EditorMode>,
              EditorMode,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
