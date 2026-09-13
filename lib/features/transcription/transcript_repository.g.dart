// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transcript_repository.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(transcriptRepository)
final transcriptRepositoryProvider = TranscriptRepositoryProvider._();

final class TranscriptRepositoryProvider
    extends
        $FunctionalProvider<
          TranscriptRepository,
          TranscriptRepository,
          TranscriptRepository
        >
    with $Provider<TranscriptRepository> {
  TranscriptRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'transcriptRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$transcriptRepositoryHash();

  @$internal
  @override
  $ProviderElement<TranscriptRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  TranscriptRepository create(Ref ref) {
    return transcriptRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TranscriptRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TranscriptRepository>(value),
    );
  }
}

String _$transcriptRepositoryHash() =>
    r'53371fb431bdeeb8b8955e905662829a4b9e5d79';

/// Whether the undo and redo controls are live for [transcriptId].

@ProviderFor(editHistory)
final editHistoryProvider = EditHistoryFamily._();

/// Whether the undo and redo controls are live for [transcriptId].

final class EditHistoryProvider
    extends
        $FunctionalProvider<
          AsyncValue<({bool canRedo, bool canUndo})>,
          ({bool canRedo, bool canUndo}),
          Stream<({bool canRedo, bool canUndo})>
        >
    with
        $FutureModifier<({bool canRedo, bool canUndo})>,
        $StreamProvider<({bool canRedo, bool canUndo})> {
  /// Whether the undo and redo controls are live for [transcriptId].
  EditHistoryProvider._({
    required EditHistoryFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'editHistoryProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$editHistoryHash();

  @override
  String toString() {
    return r'editHistoryProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<({bool canRedo, bool canUndo})> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<({bool canRedo, bool canUndo})> create(Ref ref) {
    final argument = this.argument as String;
    return editHistory(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is EditHistoryProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$editHistoryHash() => r'439dea1d8d9b647a6f3a4cb03c6eb01b36567719';

/// Whether the undo and redo controls are live for [transcriptId].

final class EditHistoryFamily extends $Family
    with
        $FunctionalFamilyOverride<
          Stream<({bool canRedo, bool canUndo})>,
          String
        > {
  EditHistoryFamily._()
    : super(
        retry: null,
        name: r'editHistoryProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Whether the undo and redo controls are live for [transcriptId].

  EditHistoryProvider call(String transcriptId) =>
      EditHistoryProvider._(argument: transcriptId, from: this);

  @override
  String toString() => r'editHistoryProvider';
}

/// Total bytes [projectId] occupies on disk: its imported media plus the
/// extracted WAV.
///
/// Surfaced in the library so consumed space is visible and attributable to a
/// project, rather than showing up only as an unexplained rise in the app's
/// size in Android settings.

@ProviderFor(projectMediaBytes)
final projectMediaBytesProvider = ProjectMediaBytesFamily._();

/// Total bytes [projectId] occupies on disk: its imported media plus the
/// extracted WAV.
///
/// Surfaced in the library so consumed space is visible and attributable to a
/// project, rather than showing up only as an unexplained rise in the app's
/// size in Android settings.

final class ProjectMediaBytesProvider
    extends $FunctionalProvider<AsyncValue<int>, int, FutureOr<int>>
    with $FutureModifier<int>, $FutureProvider<int> {
  /// Total bytes [projectId] occupies on disk: its imported media plus the
  /// extracted WAV.
  ///
  /// Surfaced in the library so consumed space is visible and attributable to a
  /// project, rather than showing up only as an unexplained rise in the app's
  /// size in Android settings.
  ProjectMediaBytesProvider._({
    required ProjectMediaBytesFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'projectMediaBytesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$projectMediaBytesHash();

  @override
  String toString() {
    return r'projectMediaBytesProvider'
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
    return projectMediaBytes(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ProjectMediaBytesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$projectMediaBytesHash() => r'9839ea1b0ba9945bae99b57547b97e51e9ddc7a3';

/// Total bytes [projectId] occupies on disk: its imported media plus the
/// extracted WAV.
///
/// Surfaced in the library so consumed space is visible and attributable to a
/// project, rather than showing up only as an unexplained rise in the app's
/// size in Android settings.

final class ProjectMediaBytesFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<int>, String> {
  ProjectMediaBytesFamily._()
    : super(
        retry: null,
        name: r'projectMediaBytesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Total bytes [projectId] occupies on disk: its imported media plus the
  /// extracted WAV.
  ///
  /// Surfaced in the library so consumed space is visible and attributable to a
  /// project, rather than showing up only as an unexplained rise in the app's
  /// size in Android settings.

  ProjectMediaBytesProvider call(String projectId) =>
      ProjectMediaBytesProvider._(argument: projectId, from: this);

  @override
  String toString() => r'projectMediaBytesProvider';
}

@ProviderFor(projectList)
final projectListProvider = ProjectListProvider._();

final class ProjectListProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Project>>,
          List<Project>,
          Stream<List<Project>>
        >
    with $FutureModifier<List<Project>>, $StreamProvider<List<Project>> {
  ProjectListProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'projectListProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$projectListHash();

  @$internal
  @override
  $StreamProviderElement<List<Project>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<Project>> create(Ref ref) {
    return projectList(ref);
  }
}

String _$projectListHash() => r'9b2123ac6cf9d09b6b226692fbcf8161352e6074';

@ProviderFor(projectById)
final projectByIdProvider = ProjectByIdFamily._();

final class ProjectByIdProvider
    extends
        $FunctionalProvider<AsyncValue<Project?>, Project?, FutureOr<Project?>>
    with $FutureModifier<Project?>, $FutureProvider<Project?> {
  ProjectByIdProvider._({
    required ProjectByIdFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'projectByIdProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$projectByIdHash();

  @override
  String toString() {
    return r'projectByIdProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Project?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<Project?> create(Ref ref) {
    final argument = this.argument as String;
    return projectById(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ProjectByIdProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$projectByIdHash() => r'f1f4103f8bf76f614e5f357cb70be7948fb4a3bd';

final class ProjectByIdFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Project?>, String> {
  ProjectByIdFamily._()
    : super(
        retry: null,
        name: r'projectByIdProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ProjectByIdProvider call(String projectId) =>
      ProjectByIdProvider._(argument: projectId, from: this);

  @override
  String toString() => r'projectByIdProvider';
}

@ProviderFor(transcriptWords)
final transcriptWordsProvider = TranscriptWordsFamily._();

final class TranscriptWordsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Word>>,
          List<Word>,
          Stream<List<Word>>
        >
    with $FutureModifier<List<Word>>, $StreamProvider<List<Word>> {
  TranscriptWordsProvider._({
    required TranscriptWordsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'transcriptWordsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$transcriptWordsHash();

  @override
  String toString() {
    return r'transcriptWordsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<Word>> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<List<Word>> create(Ref ref) {
    final argument = this.argument as String;
    return transcriptWords(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is TranscriptWordsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$transcriptWordsHash() => r'84e3fd0dd6548cfdb4ddae375392003e9ec908a4';

final class TranscriptWordsFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<Word>>, String> {
  TranscriptWordsFamily._()
    : super(
        retry: null,
        name: r'transcriptWordsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  TranscriptWordsProvider call(String transcriptId) =>
      TranscriptWordsProvider._(argument: transcriptId, from: this);

  @override
  String toString() => r'transcriptWordsProvider';
}

@ProviderFor(projectTranscript)
final projectTranscriptProvider = ProjectTranscriptFamily._();

final class ProjectTranscriptProvider
    extends
        $FunctionalProvider<
          AsyncValue<Transcript?>,
          Transcript?,
          FutureOr<Transcript?>
        >
    with $FutureModifier<Transcript?>, $FutureProvider<Transcript?> {
  ProjectTranscriptProvider._({
    required ProjectTranscriptFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'projectTranscriptProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$projectTranscriptHash();

  @override
  String toString() {
    return r'projectTranscriptProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Transcript?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Transcript?> create(Ref ref) {
    final argument = this.argument as String;
    return projectTranscript(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ProjectTranscriptProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$projectTranscriptHash() => r'f70eaa509715b229420c10feb1e6a0a33105df5c';

final class ProjectTranscriptFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Transcript?>, String> {
  ProjectTranscriptFamily._()
    : super(
        retry: null,
        name: r'projectTranscriptProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ProjectTranscriptProvider call(String projectId) =>
      ProjectTranscriptProvider._(argument: projectId, from: this);

  @override
  String toString() => r'projectTranscriptProvider';
}
