import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/database.dart';
import 'whisper_model_catalog.dart';

part 'whisper_model_controller.g.dart';

/// Settings key holding the chosen model's id.
///
/// Namespaced because [AppDatabase.readSetting] is a shared key/value store;
/// unprefixed keys would collide as soon as anything else needs persisting.
const String selectedWhisperModelSetting = 'whisper.selected_model';

/// The transcription model the app will use, persisted across launches.
///
/// Always resolved through [WhisperModelCatalog.resolve], so a stored id that
/// no longer matches a shipped model degrades to the default instead of
/// leaving the app pointing at a file that is not there.
@Riverpod(keepAlive: true)
class SelectedWhisperModel extends _$SelectedWhisperModel {
  @override
  Future<WhisperModelDescriptor?> build() async {
    final storedId =
        await ref.watch(appDatabaseProvider).readSetting(selectedWhisperModelSetting);
    return ref.watch(whisperModelCatalogProvider).resolve(storedId);
  }

  /// Switches the active model and remembers the choice.
  ///
  /// Only the id is stored. Persisting the whole descriptor would freeze this
  /// build's filename into the database, so a later release that renamed or
  /// repackaged the file would resurrect a stale path.
  Future<void> select(WhisperModelDescriptor model) async {
    await ref
        .read(appDatabaseProvider)
        .writeSetting(selectedWhisperModelSetting, model.id);
    state = AsyncData(model);
  }
}
