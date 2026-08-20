// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'import_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Drives one media file from the picker all the way to persisted words.
///
/// Every step that touches the filesystem or the engine lives here rather
/// than in a widget, so the import screen can be redesigned without moving
/// any of this logic (CLAUDE.md 4).

@ProviderFor(ImportController)
final importControllerProvider = ImportControllerProvider._();

/// Drives one media file from the picker all the way to persisted words.
///
/// Every step that touches the filesystem or the engine lives here rather
/// than in a widget, so the import screen can be redesigned without moving
/// any of this logic (CLAUDE.md 4).
final class ImportControllerProvider
    extends $NotifierProvider<ImportController, ImportStatus> {
  /// Drives one media file from the picker all the way to persisted words.
  ///
  /// Every step that touches the filesystem or the engine lives here rather
  /// than in a widget, so the import screen can be redesigned without moving
  /// any of this logic (CLAUDE.md 4).
  ImportControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'importControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$importControllerHash();

  @$internal
  @override
  ImportController create() => ImportController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ImportStatus value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ImportStatus>(value),
    );
  }
}

String _$importControllerHash() => r'ac829488d0687e8b6155b3123128ff35926c4beb';

/// Drives one media file from the picker all the way to persisted words.
///
/// Every step that touches the filesystem or the engine lives here rather
/// than in a widget, so the import screen can be redesigned without moving
/// any of this logic (CLAUDE.md 4).

abstract class _$ImportController extends $Notifier<ImportStatus> {
  ImportStatus build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ImportStatus, ImportStatus>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ImportStatus, ImportStatus>,
              ImportStatus,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
