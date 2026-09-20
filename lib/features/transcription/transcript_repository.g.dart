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

@ProviderFor(projectClips)
final projectClipsProvider = ProjectClipsFamily._();

/// A project's clips in timeline order. Empty for a project nobody has added
/// media to yet, which is the state "Create project" leaves behind.

final class ProjectClipsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<MediaClip>>,
          List<MediaClip>,
          Stream<List<MediaClip>>
        >
    with $FutureModifier<List<MediaClip>>, $StreamProvider<List<MediaClip>> {
  /// A project's clips in timeline order. Empty for a project nobody has added
  /// media to yet, which is the state "Create project" leaves behind.
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

/// A project's clips in timeline order. Empty for a project nobody has added
/// media to yet, which is the state "Create project" leaves behind.

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

  /// A project's clips in timeline order. Empty for a project nobody has added
  /// media to yet, which is the state "Create project" leaves behind.

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

String _$projectSentencesHash() => r'8c886a78526a1341d185117e4917e3a34efdc233';

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
