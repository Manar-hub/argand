import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/database.dart';
import 'whisper_model_catalog.dart';

part 'whisper_model_controller.g.dart';

/// Settings key holding the chosen model's id.
const String selectedWhisperModelSetting = 'whisper.selected_model';

/// The transcription model the app will use, persisted across launches.
@Riverpod(keepAlive: true)
class SelectedWhisperModel extends _$SelectedWhisperModel {
  @override
  Future<WhisperModelDescriptor?> build() async {
    final storedId =
        await ref.watch(appDatabaseProvider).readSetting(selectedWhisperModelSetting);
    final installed = await ref.watch(availableWhisperModelsProvider.future);
    return WhisperModelCatalog.pick(installed, storedId);
  }

  /// Switches the active model and remembers the choice.
  Future<void> select(WhisperModelDescriptor model) async {
    await ref
        .read(appDatabaseProvider)
        .writeSetting(selectedWhisperModelSetting, model.id);
    state = AsyncData(model);
  }
}
