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

/// Custom speaker labels for [transcriptId], empty when nobody has renamed one.
///
/// Keyed by transcript id rather than project so the caption overlay and the
/// transcript view read the same instance. Synchronous, with an empty map while
/// the row loads — the fallback `Speaker N` label is correct in that moment
/// anyway, so there is nothing to wait for and no spinner to show.

@ProviderFor(speakerNames)
final speakerNamesProvider = SpeakerNamesFamily._();

/// Custom speaker labels for [transcriptId], empty when nobody has renamed one.
///
/// Keyed by transcript id rather than project so the caption overlay and the
/// transcript view read the same instance. Synchronous, with an empty map while
/// the row loads — the fallback `Speaker N` label is correct in that moment
/// anyway, so there is nothing to wait for and no spinner to show.

final class SpeakerNamesProvider
    extends $FunctionalProvider<SpeakerNames, SpeakerNames, SpeakerNames>
    with $Provider<SpeakerNames> {
  /// Custom speaker labels for [transcriptId], empty when nobody has renamed one.
  ///
  /// Keyed by transcript id rather than project so the caption overlay and the
  /// transcript view read the same instance. Synchronous, with an empty map while
  /// the row loads — the fallback `Speaker N` label is correct in that moment
  /// anyway, so there is nothing to wait for and no spinner to show.
  SpeakerNamesProvider._({
    required SpeakerNamesFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'speakerNamesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$speakerNamesHash();

  @override
  String toString() {
    return r'speakerNamesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<SpeakerNames> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SpeakerNames create(Ref ref) {
    final argument = this.argument as String;
    return speakerNames(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SpeakerNames value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SpeakerNames>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SpeakerNamesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$speakerNamesHash() => r'ca47b053385677699cd0c8be96c37ba3ccfcac9e';

/// Custom speaker labels for [transcriptId], empty when nobody has renamed one.
///
/// Keyed by transcript id rather than project so the caption overlay and the
/// transcript view read the same instance. Synchronous, with an empty map while
/// the row loads — the fallback `Speaker N` label is correct in that moment
/// anyway, so there is nothing to wait for and no spinner to show.

final class SpeakerNamesFamily extends $Family
    with $FunctionalFamilyOverride<SpeakerNames, String> {
  SpeakerNamesFamily._()
    : super(
        retry: null,
        name: r'speakerNamesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Custom speaker labels for [transcriptId], empty when nobody has renamed one.
  ///
  /// Keyed by transcript id rather than project so the caption overlay and the
  /// transcript view read the same instance. Synchronous, with an empty map while
  /// the row loads — the fallback `Speaker N` label is correct in that moment
  /// anyway, so there is nothing to wait for and no spinner to show.

  SpeakerNamesProvider call(String transcriptId) =>
      SpeakerNamesProvider._(argument: transcriptId, from: this);

  @override
  String toString() => r'speakerNamesProvider';
}

@ProviderFor(transcriptById)
final transcriptByIdProvider = TranscriptByIdFamily._();

final class TranscriptByIdProvider
    extends
        $FunctionalProvider<
          AsyncValue<Transcript?>,
          Transcript?,
          Stream<Transcript?>
        >
    with $FutureModifier<Transcript?>, $StreamProvider<Transcript?> {
  TranscriptByIdProvider._({
    required TranscriptByIdFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'transcriptByIdProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$transcriptByIdHash();

  @override
  String toString() {
    return r'transcriptByIdProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<Transcript?> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<Transcript?> create(Ref ref) {
    final argument = this.argument as String;
    return transcriptById(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is TranscriptByIdProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$transcriptByIdHash() => r'ad64fdc2349b257605c09dc97174709909897302';

final class TranscriptByIdFamily extends $Family
    with $FunctionalFamilyOverride<Stream<Transcript?>, String> {
  TranscriptByIdFamily._()
    : super(
        retry: null,
        name: r'transcriptByIdProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  TranscriptByIdProvider call(String transcriptId) =>
      TranscriptByIdProvider._(argument: transcriptId, from: this);

  @override
  String toString() => r'transcriptByIdProvider';
}

/// Whether the undo and redo controls are live for [transcriptId].
/// Whether the project has anything to undo or redo.
///
/// **One history behind one pair of buttons.** Both modes read this, because
/// splitting a clip and correcting a word are the same kind of fact to someone
/// pressing undo -- which table they were stored in is not something the
/// control should have an opinion about.

@ProviderFor(projectHistoryState)
final projectHistoryStateProvider = ProjectHistoryStateFamily._();

/// Whether the undo and redo controls are live for [transcriptId].
/// Whether the project has anything to undo or redo.
///
/// **One history behind one pair of buttons.** Both modes read this, because
/// splitting a clip and correcting a word are the same kind of fact to someone
/// pressing undo -- which table they were stored in is not something the
/// control should have an opinion about.

final class ProjectHistoryStateProvider
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
  /// Whether the project has anything to undo or redo.
  ///
  /// **One history behind one pair of buttons.** Both modes read this, because
  /// splitting a clip and correcting a word are the same kind of fact to someone
  /// pressing undo -- which table they were stored in is not something the
  /// control should have an opinion about.
  ProjectHistoryStateProvider._({
    required ProjectHistoryStateFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'projectHistoryStateProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$projectHistoryStateHash();

  @override
  String toString() {
    return r'projectHistoryStateProvider'
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
    return projectHistoryState(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ProjectHistoryStateProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$projectHistoryStateHash() =>
    r'd5df89e23230fb73df06749838bf1c446caeed13';

/// Whether the undo and redo controls are live for [transcriptId].
/// Whether the project has anything to undo or redo.
///
/// **One history behind one pair of buttons.** Both modes read this, because
/// splitting a clip and correcting a word are the same kind of fact to someone
/// pressing undo -- which table they were stored in is not something the
/// control should have an opinion about.

final class ProjectHistoryStateFamily extends $Family
    with
        $FunctionalFamilyOverride<
          Stream<({bool canRedo, bool canUndo})>,
          String
        > {
  ProjectHistoryStateFamily._()
    : super(
        retry: null,
        name: r'projectHistoryStateProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Whether the undo and redo controls are live for [transcriptId].
  /// Whether the project has anything to undo or redo.
  ///
  /// **One history behind one pair of buttons.** Both modes read this, because
  /// splitting a clip and correcting a word are the same kind of fact to someone
  /// pressing undo -- which table they were stored in is not something the
  /// control should have an opinion about.

  ProjectHistoryStateProvider call(String projectId) =>
      ProjectHistoryStateProvider._(argument: projectId, from: this);

  @override
  String toString() => r'projectHistoryStateProvider';
}

@ProviderFor(editHistory)
final editHistoryProvider = EditHistoryFamily._();

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

/// The library's search results for [query]: projects by title or by what
/// their transcripts say. See `AppDatabase.searchLibrary`.

@ProviderFor(librarySearch)
final librarySearchProvider = LibrarySearchFamily._();

/// The library's search results for [query]: projects by title or by what
/// their transcripts say. See `AppDatabase.searchLibrary`.

final class LibrarySearchProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<LibraryHit>>,
          List<LibraryHit>,
          Stream<List<LibraryHit>>
        >
    with $FutureModifier<List<LibraryHit>>, $StreamProvider<List<LibraryHit>> {
  /// The library's search results for [query]: projects by title or by what
  /// their transcripts say. See `AppDatabase.searchLibrary`.
  LibrarySearchProvider._({
    required LibrarySearchFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'librarySearchProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$librarySearchHash();

  @override
  String toString() {
    return r'librarySearchProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<LibraryHit>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<LibraryHit>> create(Ref ref) {
    final argument = this.argument as String;
    return librarySearch(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is LibrarySearchProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$librarySearchHash() => r'e525f274371e6555078f36a05249b32837554ce1';

/// The library's search results for [query]: projects by title or by what
/// their transcripts say. See `AppDatabase.searchLibrary`.

final class LibrarySearchFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<LibraryHit>>, String> {
  LibrarySearchFamily._()
    : super(
        retry: null,
        name: r'librarySearchProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The library's search results for [query]: projects by title or by what
  /// their transcripts say. See `AppDatabase.searchLibrary`.

  LibrarySearchProvider call(String query) =>
      LibrarySearchProvider._(argument: query, from: this);

  @override
  String toString() => r'librarySearchProvider';
}

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

/// Every transcript covering one clip, earliest range first. Empty when
/// nothing on the clip has been transcribed yet.
///
/// Speaker names live on these rows, so a rename has to reach the transcript
/// view, the caption overlay and the export button with nothing being told to
/// refresh.

@ProviderFor(clipTranscripts)
final clipTranscriptsProvider = ClipTranscriptsFamily._();

/// Every transcript covering one clip, earliest range first. Empty when
/// nothing on the clip has been transcribed yet.
///
/// Speaker names live on these rows, so a rename has to reach the transcript
/// view, the caption overlay and the export button with nothing being told to
/// refresh.

final class ClipTranscriptsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Transcript>>,
          List<Transcript>,
          Stream<List<Transcript>>
        >
    with $FutureModifier<List<Transcript>>, $StreamProvider<List<Transcript>> {
  /// Every transcript covering one clip, earliest range first. Empty when
  /// nothing on the clip has been transcribed yet.
  ///
  /// Speaker names live on these rows, so a rename has to reach the transcript
  /// view, the caption overlay and the export button with nothing being told to
  /// refresh.
  ClipTranscriptsProvider._({
    required ClipTranscriptsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'clipTranscriptsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$clipTranscriptsHash();

  @override
  String toString() {
    return r'clipTranscriptsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<Transcript>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<Transcript>> create(Ref ref) {
    final argument = this.argument as String;
    return clipTranscripts(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ClipTranscriptsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$clipTranscriptsHash() => r'13bbc2d0a7abeb98e132100afbe33016ad34efa0';

/// Every transcript covering one clip, earliest range first. Empty when
/// nothing on the clip has been transcribed yet.
///
/// Speaker names live on these rows, so a rename has to reach the transcript
/// view, the caption overlay and the export button with nothing being told to
/// refresh.

final class ClipTranscriptsFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<Transcript>>, String> {
  ClipTranscriptsFamily._()
    : super(
        retry: null,
        name: r'clipTranscriptsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Every transcript covering one clip, earliest range first. Empty when
  /// nothing on the clip has been transcribed yet.
  ///
  /// Speaker names live on these rows, so a rename has to reach the transcript
  /// view, the caption overlay and the export button with nothing being told to
  /// refresh.

  ClipTranscriptsProvider call(String clipId) =>
      ClipTranscriptsProvider._(argument: clipId, from: this);

  @override
  String toString() => r'clipTranscriptsProvider';
}

@ProviderFor(projectScript)
final projectScriptProvider = ProjectScriptFamily._();

final class ProjectScriptProvider
    extends $FunctionalProvider<ProjectScript, ProjectScript, ProjectScript>
    with $Provider<ProjectScript> {
  ProjectScriptProvider._({
    required ProjectScriptFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'projectScriptProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$projectScriptHash();

  @override
  String toString() {
    return r'projectScriptProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<ProjectScript> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ProjectScript create(Ref ref) {
    final argument = this.argument as String;
    return projectScript(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProjectScript value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProjectScript>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ProjectScriptProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$projectScriptHash() => r'0947d0b6e4b62d1282d4cc8a1e5757614dcf1d07';

final class ProjectScriptFamily extends $Family
    with $FunctionalFamilyOverride<ProjectScript, String> {
  ProjectScriptFamily._()
    : super(
        retry: null,
        name: r'projectScriptProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ProjectScriptProvider call(String projectId) =>
      ProjectScriptProvider._(argument: projectId, from: this);

  @override
  String toString() => r'projectScriptProvider';
}

/// A project's transcribe layers, in timeline order.

@ProviderFor(projectLayers)
final projectLayersProvider = ProjectLayersFamily._();

/// A project's transcribe layers, in timeline order.

final class ProjectLayersProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<TranscribeLayer>>,
          List<TranscribeLayer>,
          Stream<List<TranscribeLayer>>
        >
    with
        $FutureModifier<List<TranscribeLayer>>,
        $StreamProvider<List<TranscribeLayer>> {
  /// A project's transcribe layers, in timeline order.
  ProjectLayersProvider._({
    required ProjectLayersFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'projectLayersProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$projectLayersHash();

  @override
  String toString() {
    return r'projectLayersProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<TranscribeLayer>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<TranscribeLayer>> create(Ref ref) {
    final argument = this.argument as String;
    return projectLayers(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ProjectLayersProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$projectLayersHash() => r'719b43f6e6934d8d6d6c559aa3c7c011835bfdaa';

/// A project's transcribe layers, in timeline order.

final class ProjectLayersFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<TranscribeLayer>>, String> {
  ProjectLayersFamily._()
    : super(
        retry: null,
        name: r'projectLayersProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// A project's transcribe layers, in timeline order.

  ProjectLayersProvider call(String projectId) =>
      ProjectLayersProvider._(argument: projectId, from: this);

  @override
  String toString() => r'projectLayersProvider';
}

/// A project's clips in timeline order. Empty for a project nobody has added
/// media to yet, which is the state "Create project" leaves behind.
/// A transcript's translation, one line per sentence; empty when it has none.

@ProviderFor(transcriptTranslation)
final transcriptTranslationProvider = TranscriptTranslationFamily._();

/// A project's clips in timeline order. Empty for a project nobody has added
/// media to yet, which is the state "Create project" leaves behind.
/// A transcript's translation, one line per sentence; empty when it has none.

final class TranscriptTranslationProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<TranslationLine>>,
          List<TranslationLine>,
          Stream<List<TranslationLine>>
        >
    with
        $FutureModifier<List<TranslationLine>>,
        $StreamProvider<List<TranslationLine>> {
  /// A project's clips in timeline order. Empty for a project nobody has added
  /// media to yet, which is the state "Create project" leaves behind.
  /// A transcript's translation, one line per sentence; empty when it has none.
  TranscriptTranslationProvider._({
    required TranscriptTranslationFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'transcriptTranslationProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$transcriptTranslationHash();

  @override
  String toString() {
    return r'transcriptTranslationProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<TranslationLine>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<TranslationLine>> create(Ref ref) {
    final argument = this.argument as String;
    return transcriptTranslation(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is TranscriptTranslationProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$transcriptTranslationHash() =>
    r'494f483c65f0aeb1c574e1d34b7e8dbd3a0b8c24';

/// A project's clips in timeline order. Empty for a project nobody has added
/// media to yet, which is the state "Create project" leaves behind.
/// A transcript's translation, one line per sentence; empty when it has none.

final class TranscriptTranslationFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<TranslationLine>>, String> {
  TranscriptTranslationFamily._()
    : super(
        retry: null,
        name: r'transcriptTranslationProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// A project's clips in timeline order. Empty for a project nobody has added
  /// media to yet, which is the state "Create project" leaves behind.
  /// A transcript's translation, one line per sentence; empty when it has none.

  TranscriptTranslationProvider call(String transcriptId) =>
      TranscriptTranslationProvider._(argument: transcriptId, from: this);

  @override
  String toString() => r'transcriptTranslationProvider';
}

/// Every translation line in a project as a text over the picture, for the
/// stage. See `translation_texts.dart`.

@ProviderFor(projectTranslationTexts)
final projectTranslationTextsProvider = ProjectTranslationTextsFamily._();

/// Every translation line in a project as a text over the picture, for the
/// stage. See `translation_texts.dart`.

final class ProjectTranslationTextsProvider
    extends
        $FunctionalProvider<List<TextLayer>, List<TextLayer>, List<TextLayer>>
    with $Provider<List<TextLayer>> {
  /// Every translation line in a project as a text over the picture, for the
  /// stage. See `translation_texts.dart`.
  ProjectTranslationTextsProvider._({
    required ProjectTranslationTextsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'projectTranslationTextsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$projectTranslationTextsHash();

  @override
  String toString() {
    return r'projectTranslationTextsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<List<TextLayer>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  List<TextLayer> create(Ref ref) {
    final argument = this.argument as String;
    return projectTranslationTexts(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<TextLayer> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<TextLayer>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ProjectTranslationTextsProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$projectTranslationTextsHash() =>
    r'a20081c54e90020e1a8aa6c0bf8b9c04123db339';

/// Every translation line in a project as a text over the picture, for the
/// stage. See `translation_texts.dart`.

final class ProjectTranslationTextsFamily extends $Family
    with $FunctionalFamilyOverride<List<TextLayer>, String> {
  ProjectTranslationTextsFamily._()
    : super(
        retry: null,
        name: r'projectTranslationTextsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Every translation line in a project as a text over the picture, for the
  /// stage. See `translation_texts.dart`.

  ProjectTranslationTextsProvider call(String projectId) =>
      ProjectTranslationTextsProvider._(argument: projectId, from: this);

  @override
  String toString() => r'projectTranslationTextsProvider';
}

/// A project's tracks, top to bottom -- placing anything not yet on one the
/// first time the project is watched.

@ProviderFor(projectTracks)
final projectTracksProvider = ProjectTracksFamily._();

/// A project's tracks, top to bottom -- placing anything not yet on one the
/// first time the project is watched.

final class ProjectTracksProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Track>>,
          List<Track>,
          Stream<List<Track>>
        >
    with $FutureModifier<List<Track>>, $StreamProvider<List<Track>> {
  /// A project's tracks, top to bottom -- placing anything not yet on one the
  /// first time the project is watched.
  ProjectTracksProvider._({
    required ProjectTracksFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'projectTracksProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$projectTracksHash();

  @override
  String toString() {
    return r'projectTracksProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<Track>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<Track>> create(Ref ref) {
    final argument = this.argument as String;
    return projectTracks(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ProjectTracksProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$projectTracksHash() => r'd017d66ac60587b5743033e5b7d78617ac21c5b0';

/// A project's tracks, top to bottom -- placing anything not yet on one the
/// first time the project is watched.

final class ProjectTracksFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<Track>>, String> {
  ProjectTracksFamily._()
    : super(
        retry: null,
        name: r'projectTracksProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// A project's tracks, top to bottom -- placing anything not yet on one the
  /// first time the project is watched.

  ProjectTracksProvider call(String projectId) =>
      ProjectTracksProvider._(argument: projectId, from: this);

  @override
  String toString() => r'projectTracksProvider';
}

/// A project's images in timeline order.

@ProviderFor(projectImageLayers)
final projectImageLayersProvider = ProjectImageLayersFamily._();

/// A project's images in timeline order.

final class ProjectImageLayersProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ImageLayer>>,
          List<ImageLayer>,
          Stream<List<ImageLayer>>
        >
    with $FutureModifier<List<ImageLayer>>, $StreamProvider<List<ImageLayer>> {
  /// A project's images in timeline order.
  ProjectImageLayersProvider._({
    required ProjectImageLayersFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'projectImageLayersProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$projectImageLayersHash();

  @override
  String toString() {
    return r'projectImageLayersProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<ImageLayer>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<ImageLayer>> create(Ref ref) {
    final argument = this.argument as String;
    return projectImageLayers(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ProjectImageLayersProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$projectImageLayersHash() =>
    r'f489a96f77c0884ab2c645b5871b3fb6953a8894';

/// A project's images in timeline order.

final class ProjectImageLayersFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<ImageLayer>>, String> {
  ProjectImageLayersFamily._()
    : super(
        retry: null,
        name: r'projectImageLayersProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// A project's images in timeline order.

  ProjectImageLayersProvider call(String projectId) =>
      ProjectImageLayersProvider._(argument: projectId, from: this);

  @override
  String toString() => r'projectImageLayersProvider';
}

/// Every translation line in a project, in project time, in order.

@ProviderFor(projectTranslationLines)
final projectTranslationLinesProvider = ProjectTranslationLinesFamily._();

/// Every translation line in a project, in project time, in order.

final class ProjectTranslationLinesProvider
    extends
        $FunctionalProvider<
          List<ProjectTranslationLine>,
          List<ProjectTranslationLine>,
          List<ProjectTranslationLine>
        >
    with $Provider<List<ProjectTranslationLine>> {
  /// Every translation line in a project, in project time, in order.
  ProjectTranslationLinesProvider._({
    required ProjectTranslationLinesFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'projectTranslationLinesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$projectTranslationLinesHash();

  @override
  String toString() {
    return r'projectTranslationLinesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<List<ProjectTranslationLine>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  List<ProjectTranslationLine> create(Ref ref) {
    final argument = this.argument as String;
    return projectTranslationLines(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<ProjectTranslationLine> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<ProjectTranslationLine>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ProjectTranslationLinesProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$projectTranslationLinesHash() =>
    r'9cbf6a814c275f6bd002c4754bf0ad9db90cc307';

/// Every translation line in a project, in project time, in order.

final class ProjectTranslationLinesFamily extends $Family
    with $FunctionalFamilyOverride<List<ProjectTranslationLine>, String> {
  ProjectTranslationLinesFamily._()
    : super(
        retry: null,
        name: r'projectTranslationLinesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Every translation line in a project, in project time, in order.

  ProjectTranslationLinesProvider call(String projectId) =>
      ProjectTranslationLinesProvider._(argument: projectId, from: this);

  @override
  String toString() => r'projectTranslationLinesProvider';
}

/// A project's text layers in timeline order.

@ProviderFor(projectTextLayers)
final projectTextLayersProvider = ProjectTextLayersFamily._();

/// A project's text layers in timeline order.

final class ProjectTextLayersProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<TextLayer>>,
          List<TextLayer>,
          Stream<List<TextLayer>>
        >
    with $FutureModifier<List<TextLayer>>, $StreamProvider<List<TextLayer>> {
  /// A project's text layers in timeline order.
  ProjectTextLayersProvider._({
    required ProjectTextLayersFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'projectTextLayersProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$projectTextLayersHash();

  @override
  String toString() {
    return r'projectTextLayersProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<TextLayer>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<TextLayer>> create(Ref ref) {
    final argument = this.argument as String;
    return projectTextLayers(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ProjectTextLayersProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$projectTextLayersHash() => r'c85afd72a9d93ac671b18405853d7c3195db4533';

/// A project's text layers in timeline order.

final class ProjectTextLayersFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<TextLayer>>, String> {
  ProjectTextLayersFamily._()
    : super(
        retry: null,
        name: r'projectTextLayersProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// A project's text layers in timeline order.

  ProjectTextLayersProvider call(String projectId) =>
      ProjectTextLayersProvider._(argument: projectId, from: this);

  @override
  String toString() => r'projectTextLayersProvider';
}

@ProviderFor(projectClips)
final projectClipsProvider = ProjectClipsFamily._();

final class ProjectClipsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<MediaClip>>,
          List<MediaClip>,
          Stream<List<MediaClip>>
        >
    with $FutureModifier<List<MediaClip>>, $StreamProvider<List<MediaClip>> {
  ProjectClipsProvider._({
    required ProjectClipsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'projectClipsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$projectClipsHash();

  @override
  String toString() {
    return r'projectClipsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<MediaClip>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<MediaClip>> create(Ref ref) {
    final argument = this.argument as String;
    return projectClips(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ProjectClipsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$projectClipsHash() => r'a7d7b988b97250e4aba927803acb6a82e3545406';

final class ProjectClipsFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<MediaClip>>, String> {
  ProjectClipsFamily._()
    : super(
        retry: null,
        name: r'projectClipsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ProjectClipsProvider call(String projectId) =>
      ProjectClipsProvider._(argument: projectId, from: this);

  @override
  String toString() => r'projectClipsProvider';
}

/// Where each of a project's clips falls on one shared time axis.
///
/// The single copy of the running sum. The ruler, the track, the playhead and
/// anything turning a drawn range back into per-clip work all measure with
/// this — an earlier pass had the ruler and the track folding their own totals
/// and they drifted apart, which is the bug this exists to make impossible.

@ProviderFor(projectTimeline)
final projectTimelineProvider = ProjectTimelineFamily._();

/// Where each of a project's clips falls on one shared time axis.
///
/// The single copy of the running sum. The ruler, the track, the playhead and
/// anything turning a drawn range back into per-clip work all measure with
/// this — an earlier pass had the ruler and the track folding their own totals
/// and they drifted apart, which is the bug this exists to make impossible.

final class ProjectTimelineProvider
    extends
        $FunctionalProvider<ProjectTimeline, ProjectTimeline, ProjectTimeline>
    with $Provider<ProjectTimeline> {
  /// Where each of a project's clips falls on one shared time axis.
  ///
  /// The single copy of the running sum. The ruler, the track, the playhead and
  /// anything turning a drawn range back into per-clip work all measure with
  /// this — an earlier pass had the ruler and the track folding their own totals
  /// and they drifted apart, which is the bug this exists to make impossible.
  ProjectTimelineProvider._({
    required ProjectTimelineFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'projectTimelineProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$projectTimelineHash();

  @override
  String toString() {
    return r'projectTimelineProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<ProjectTimeline> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ProjectTimeline create(Ref ref) {
    final argument = this.argument as String;
    return projectTimeline(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProjectTimeline value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProjectTimeline>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ProjectTimelineProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$projectTimelineHash() => r'3e8346dd248f27d44a2a8f6b18c7ceea074b9371';

/// Where each of a project's clips falls on one shared time axis.
///
/// The single copy of the running sum. The ruler, the track, the playhead and
/// anything turning a drawn range back into per-clip work all measure with
/// this — an earlier pass had the ruler and the track folding their own totals
/// and they drifted apart, which is the bug this exists to make impossible.

final class ProjectTimelineFamily extends $Family
    with $FunctionalFamilyOverride<ProjectTimeline, String> {
  ProjectTimelineFamily._()
    : super(
        retry: null,
        name: r'projectTimelineProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Where each of a project's clips falls on one shared time axis.
  ///
  /// The single copy of the running sum. The ruler, the track, the playhead and
  /// anything turning a drawn range back into per-clip work all measure with
  /// this — an earlier pass had the ruler and the track folding their own totals
  /// and they drifted apart, which is the bug this exists to make impossible.

  ProjectTimelineProvider call(String projectId) =>
      ProjectTimelineProvider._(argument: projectId, from: this);

  @override
  String toString() => r'projectTimelineProvider';
}

/// The amplitude readings behind a clip's audio lane, computed on first need.
///
/// **Not computed at import.** Deriving these costs a full native decode of
/// the media, and "+" is specified to copy a file in and do nothing else — so
/// the lane fills in once the timeline asks for it, and a clip added a moment
/// ago legitimately draws flat until it does.
///
/// Returns an empty list while computing and for media that has no decodable
/// audio; both cases draw as a flat lane. The result is stored on the clip, so
/// this decodes once per clip ever rather than once per visit.

@ProviderFor(clipWaveform)
final clipWaveformProvider = ClipWaveformFamily._();

/// The amplitude readings behind a clip's audio lane, computed on first need.
///
/// **Not computed at import.** Deriving these costs a full native decode of
/// the media, and "+" is specified to copy a file in and do nothing else — so
/// the lane fills in once the timeline asks for it, and a clip added a moment
/// ago legitimately draws flat until it does.
///
/// Returns an empty list while computing and for media that has no decodable
/// audio; both cases draw as a flat lane. The result is stored on the clip, so
/// this decodes once per clip ever rather than once per visit.

final class ClipWaveformProvider
    extends
        $FunctionalProvider<
          AsyncValue<Uint8List>,
          Uint8List,
          FutureOr<Uint8List>
        >
    with $FutureModifier<Uint8List>, $FutureProvider<Uint8List> {
  /// The amplitude readings behind a clip's audio lane, computed on first need.
  ///
  /// **Not computed at import.** Deriving these costs a full native decode of
  /// the media, and "+" is specified to copy a file in and do nothing else — so
  /// the lane fills in once the timeline asks for it, and a clip added a moment
  /// ago legitimately draws flat until it does.
  ///
  /// Returns an empty list while computing and for media that has no decodable
  /// audio; both cases draw as a flat lane. The result is stored on the clip, so
  /// this decodes once per clip ever rather than once per visit.
  ClipWaveformProvider._({
    required ClipWaveformFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'clipWaveformProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$clipWaveformHash();

  @override
  String toString() {
    return r'clipWaveformProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Uint8List> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<Uint8List> create(Ref ref) {
    final argument = this.argument as String;
    return clipWaveform(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ClipWaveformProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$clipWaveformHash() => r'4d3e713f370b5755a81eb3617bfa18d3b31ecbc4';

/// The amplitude readings behind a clip's audio lane, computed on first need.
///
/// **Not computed at import.** Deriving these costs a full native decode of
/// the media, and "+" is specified to copy a file in and do nothing else — so
/// the lane fills in once the timeline asks for it, and a clip added a moment
/// ago legitimately draws flat until it does.
///
/// Returns an empty list while computing and for media that has no decodable
/// audio; both cases draw as a flat lane. The result is stored on the clip, so
/// this decodes once per clip ever rather than once per visit.

final class ClipWaveformFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Uint8List>, String> {
  ClipWaveformFamily._()
    : super(
        retry: null,
        name: r'clipWaveformProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The amplitude readings behind a clip's audio lane, computed on first need.
  ///
  /// **Not computed at import.** Deriving these costs a full native decode of
  /// the media, and "+" is specified to copy a file in and do nothing else — so
  /// the lane fills in once the timeline asks for it, and a clip added a moment
  /// ago legitimately draws flat until it does.
  ///
  /// Returns an empty list while computing and for media that has no decodable
  /// audio; both cases draw as a flat lane. The result is stored on the clip, so
  /// this decodes once per clip ever rather than once per visit.

  ClipWaveformProvider call(String clipId) =>
      ClipWaveformProvider._(argument: clipId, from: this);

  @override
  String toString() => r'clipWaveformProvider';
}

/// Every transcribed sentence in a project, in timeline order.
///
/// A thin assembly over [sentencesForClip]: this walks the project's clips and
/// their transcripts, and that does the placing. The arithmetic lives there so
/// it can be tested without a database.

@ProviderFor(projectSentences)
final projectSentencesProvider = ProjectSentencesFamily._();

/// Every transcribed sentence in a project, in timeline order.
///
/// A thin assembly over [sentencesForClip]: this walks the project's clips and
/// their transcripts, and that does the placing. The arithmetic lives there so
/// it can be tested without a database.

final class ProjectSentencesProvider
    extends
        $FunctionalProvider<
          List<TimelineSentence>,
          List<TimelineSentence>,
          List<TimelineSentence>
        >
    with $Provider<List<TimelineSentence>> {
  /// Every transcribed sentence in a project, in timeline order.
  ///
  /// A thin assembly over [sentencesForClip]: this walks the project's clips and
  /// their transcripts, and that does the placing. The arithmetic lives there so
  /// it can be tested without a database.
  ProjectSentencesProvider._({
    required ProjectSentencesFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'projectSentencesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$projectSentencesHash();

  @override
  String toString() {
    return r'projectSentencesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<List<TimelineSentence>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  List<TimelineSentence> create(Ref ref) {
    final argument = this.argument as String;
    return projectSentences(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<TimelineSentence> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<TimelineSentence>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ProjectSentencesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$projectSentencesHash() => r'ddebf4564be8579f95fc115af3c20b286049b181';

/// Every transcribed sentence in a project, in timeline order.
///
/// A thin assembly over [sentencesForClip]: this walks the project's clips and
/// their transcripts, and that does the placing. The arithmetic lives there so
/// it can be tested without a database.

final class ProjectSentencesFamily extends $Family
    with $FunctionalFamilyOverride<List<TimelineSentence>, String> {
  ProjectSentencesFamily._()
    : super(
        retry: null,
        name: r'projectSentencesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Every transcribed sentence in a project, in timeline order.
  ///
  /// A thin assembly over [sentencesForClip]: this walks the project's clips and
  /// their transcripts, and that does the placing. The arithmetic lives there so
  /// it can be tested without a database.

  ProjectSentencesProvider call(String projectId) =>
      ProjectSentencesProvider._(argument: projectId, from: this);

  @override
  String toString() => r'projectSentencesProvider';
}

/// A project's running time, for the library row.
///
/// Clips whose duration could not be probed contribute nothing rather than
/// making the whole total unknown — a slightly short number reads better in the
/// library than a blank one.

@ProviderFor(projectDuration)
final projectDurationProvider = ProjectDurationFamily._();

/// A project's running time, for the library row.
///
/// Clips whose duration could not be probed contribute nothing rather than
/// making the whole total unknown — a slightly short number reads better in the
/// library than a blank one.

final class ProjectDurationProvider
    extends $FunctionalProvider<Duration, Duration, Duration>
    with $Provider<Duration> {
  /// A project's running time, for the library row.
  ///
  /// Clips whose duration could not be probed contribute nothing rather than
  /// making the whole total unknown — a slightly short number reads better in the
  /// library than a blank one.
  ProjectDurationProvider._({
    required ProjectDurationFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'projectDurationProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$projectDurationHash();

  @override
  String toString() {
    return r'projectDurationProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<Duration> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Duration create(Ref ref) {
    final argument = this.argument as String;
    return projectDuration(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Duration value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Duration>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ProjectDurationProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$projectDurationHash() => r'5bb4128b1561a87e7024ee107d3f390e000e1315';

/// A project's running time, for the library row.
///
/// Clips whose duration could not be probed contribute nothing rather than
/// making the whole total unknown — a slightly short number reads better in the
/// library than a blank one.

final class ProjectDurationFamily extends $Family
    with $FunctionalFamilyOverride<Duration, String> {
  ProjectDurationFamily._()
    : super(
        retry: null,
        name: r'projectDurationProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// A project's running time, for the library row.
  ///
  /// Clips whose duration could not be probed contribute nothing rather than
  /// making the whole total unknown — a slightly short number reads better in the
  /// library than a blank one.

  ProjectDurationProvider call(String projectId) =>
      ProjectDurationProvider._(argument: projectId, from: this);

  @override
  String toString() => r'projectDurationProvider';
}
