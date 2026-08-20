import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/database.dart';

part 'diarization_controller.g.dart';

const String diarizationSetting = 'diarization.enabled';

/// Whether imports label who is speaking.
///
/// On by default: CLAUDE.md 2 lists diarization among the core features that
/// are free and never gated, so it should happen without being asked for.
///
/// It is still a setting because it is the most expensive optional stage in the
/// pipeline — two extra models and a whole-waveform pass — and it earns nothing
/// on single-speaker media, which is most of what this app is aimed at. A user
/// who knows their video is one person talking can switch it off and get a
/// faster import, and the toggle also makes the accuracy claim measurable on
/// real media rather than only asserted.
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
