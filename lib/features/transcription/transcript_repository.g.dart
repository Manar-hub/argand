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

/// One clip's transcript, watched rather than fetched, or null when it has not
/// been transcribed yet.
///
/// Speaker names live on this row, so a rename has to reach the transcript
/// view, the caption overlay and the export button with nothing being told to
/// refresh.

@ProviderFor(clipTranscript)
final clipTranscriptProvider = ClipTranscriptFamily._();

/// One clip's transcript, watched rather than fetched, or null when it has not
/// been transcribed yet.
///
/// Speaker names live on this row, so a rename has to reach the transcript
/// view, the caption overlay and the export button with nothing being told to
/// refresh.

final class ClipTranscriptProvider
    extends
        $FunctionalProvider<
          AsyncValue<Transcript?>,
          Transcript?,
          Stream<Transcript?>
        >
    with $FutureModifier<Transcript?>, $StreamProvider<Transcript?> {
  /// One clip's transcript, watched rather than fetched, or null when it has not
  /// been transcribed yet.
  ///
  /// Speaker names live on this row, so a rename has to reach the transcript
  /// view, the caption overlay and the export button with nothing being told to
  /// refresh.
  ClipTranscriptProvider._({
    required ClipTranscriptFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'clipTranscriptProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$clipTranscriptHash();

  @override
  String toString() {
    return r'clipTranscriptProvider'
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
    return clipTranscript(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ClipTranscriptProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$clipTranscriptHash() => r'dbb62793737613497f77caad89e7dcecebbc2021';

/// One clip's transcript, watched rather than fetched, or null when it has not
/// been transcribed yet.
///
/// Speaker names live on this row, so a rename has to reach the transcript
/// view, the caption overlay and the export button with nothing being told to
/// refresh.

final class ClipTranscriptFamily extends $Family
    with $FunctionalFamilyOverride<Stream<Transcript?>, String> {
  ClipTranscriptFamily._()
    : super(
        retry: null,
        name: r'clipTranscriptProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One clip's transcript, watched rather than fetched, or null when it has not
  /// been transcribed yet.
  ///
  /// Speaker names live on this row, so a rename has to reach the transcript
  /// view, the caption overlay and the export button with nothing being told to
  /// refresh.

  ClipTranscriptProvider call(String clipId) =>
      ClipTranscriptProvider._(argument: clipId, from: this);

  @override
  String toString() => r'clipTranscriptProvider';
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

/// A project's running time: the sum of its clips' durations.
///
/// Clips whose duration could not be probed contribute nothing rather than
/// making the whole total unknown — a slightly short number reads better in the
/// library than a blank one.

@ProviderFor(projectDuration)
final projectDurationProvider = ProjectDurationFamily._();

/// A project's running time: the sum of its clips' durations.
///
/// Clips whose duration could not be probed contribute nothing rather than
/// making the whole total unknown — a slightly short number reads better in the
/// library than a blank one.

final class ProjectDurationProvider
    extends $FunctionalProvider<Duration, Duration, Duration>
    with $Provider<Duration> {
  /// A project's running time: the sum of its clips' durations.
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

String _$projectDurationHash() => r'9c9074daa6c0dd6d69e46f12b9446a750a3037c6';

/// A project's running time: the sum of its clips' durations.
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

  /// A project's running time: the sum of its clips' durations.
  ///
  /// Clips whose duration could not be probed contribute nothing rather than
  /// making the whole total unknown — a slightly short number reads better in the
  /// library than a blank one.

  ProjectDurationProvider call(String projectId) =>
      ProjectDurationProvider._(argument: projectId, from: this);

  @override
  String toString() => r'projectDurationProvider';
}
