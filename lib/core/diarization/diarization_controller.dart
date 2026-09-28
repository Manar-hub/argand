import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/database.dart';

part 'diarization_controller.g.dart';

const String diarizationSetting = 'diarization.enabled';

/// Whether imports label who is speaking.
@Riverpod(keepAlive: true)
class SpeakerDiarizationEnabled extends _$SpeakerDiarizationEnabled {
  static const bool defaultEnabled = true;

  @override
  Future<bool> build() async {
    final stored =
        await ref.watch(appDatabaseProvider).readSetting(diarizationSetting);
    // Absent means never chosen, which is not the same as chosen-false — so
    // the default applies rather than a bare `stored == 'true'`.
    if (stored == null) return defaultEnabled;
    return stored == 'true';
  }

  Future<void> setEnabled(bool enabled) async {
    await ref
        .read(appDatabaseProvider)
        .writeSetting(diarizationSetting, enabled.toString());
    state = AsyncData(enabled);
  }
}
