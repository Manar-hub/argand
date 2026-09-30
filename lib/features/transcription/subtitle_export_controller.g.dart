// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'subtitle_export_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Writes a transcript out as a subtitle file.

@ProviderFor(SubtitleExporter)
final subtitleExporterProvider = SubtitleExporterProvider._();

/// Writes a transcript out as a subtitle file.
final class SubtitleExporterProvider
    extends $NotifierProvider<SubtitleExporter, SubtitleExportStatus> {
  /// Writes a transcript out as a subtitle file.
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

String _$subtitleExporterHash() => r'dc85eb192b894a8f03b177c9e5061115bdf303f2';

/// Writes a transcript out as a subtitle file.

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
