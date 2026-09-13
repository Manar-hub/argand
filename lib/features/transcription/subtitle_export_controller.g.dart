// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'subtitle_export_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Writes a transcript out as a subtitle file.
///
/// **Nothing here is gated.** A subtitle file is the user's own transcript in a
/// different wrapper, and CLAUDE.md §2 puts every such container on the free
/// side of the line — the paid tier begins at professional interchange formats,
/// which these are not.
///
/// Cues are regrouped from the words at export time rather than read from
/// anywhere cached, exactly as the on-screen captions are. The file therefore
/// always reflects the latest correction, including one made and then undone a
/// moment earlier.

@ProviderFor(SubtitleExporter)
final subtitleExporterProvider = SubtitleExporterProvider._();

/// Writes a transcript out as a subtitle file.
///
/// **Nothing here is gated.** A subtitle file is the user's own transcript in a
/// different wrapper, and CLAUDE.md §2 puts every such container on the free
/// side of the line — the paid tier begins at professional interchange formats,
/// which these are not.
///
/// Cues are regrouped from the words at export time rather than read from
/// anywhere cached, exactly as the on-screen captions are. The file therefore
/// always reflects the latest correction, including one made and then undone a
/// moment earlier.
final class SubtitleExporterProvider
    extends $NotifierProvider<SubtitleExporter, SubtitleExportStatus> {
  /// Writes a transcript out as a subtitle file.
  ///
  /// **Nothing here is gated.** A subtitle file is the user's own transcript in a
  /// different wrapper, and CLAUDE.md §2 puts every such container on the free
  /// side of the line — the paid tier begins at professional interchange formats,
  /// which these are not.
  ///
  /// Cues are regrouped from the words at export time rather than read from
  /// anywhere cached, exactly as the on-screen captions are. The file therefore
  /// always reflects the latest correction, including one made and then undone a
  /// moment earlier.
  SubtitleExporterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'subtitleExporterProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$subtitleExporterHash();

  @$internal
  @override
  SubtitleExporter create() => SubtitleExporter();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SubtitleExportStatus value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SubtitleExportStatus>(value),
    );
  }
}

String _$subtitleExporterHash() => r'c45ab919c3d18414d2741742b5b2bcd8030fa7b2';

/// Writes a transcript out as a subtitle file.
///
/// **Nothing here is gated.** A subtitle file is the user's own transcript in a
/// different wrapper, and CLAUDE.md §2 puts every such container on the free
/// side of the line — the paid tier begins at professional interchange formats,
/// which these are not.
///
/// Cues are regrouped from the words at export time rather than read from
/// anywhere cached, exactly as the on-screen captions are. The file therefore
/// always reflects the latest correction, including one made and then undone a
/// moment earlier.

abstract class _$SubtitleExporter extends $Notifier<SubtitleExportStatus> {
  SubtitleExportStatus build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<SubtitleExportStatus, SubtitleExportStatus>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SubtitleExportStatus, SubtitleExportStatus>,
              SubtitleExportStatus,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
