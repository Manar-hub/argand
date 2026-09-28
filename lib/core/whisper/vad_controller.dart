import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/database.dart';

part 'vad_controller.g.dart';

const String silenceSkippingSetting = 'whisper.vad';

/// Whether whisper.cpp is told to transcribe only the speech regions of a file.
@Riverpod(keepAlive: true)
class SilenceSkippingEnabled extends _$SilenceSkippingEnabled {
  static const bool defaultEnabled = true;

  @override
  Future<bool> build() async {
    final stored =
        await ref.watch(appDatabaseProvider).readSetting(silenceSkippingSetting);
    // Absent means never chosen, which is not the same as chosen-false — so
    // the default applies rather than a bare `stored == 'true'`.
    if (stored == null) return defaultEnabled;
    return stored == 'true';
  }

  Future<void> setEnabled(bool enabled) async {
    await ref
        .read(appDatabaseProvider)
        .writeSetting(silenceSkippingSetting, enabled.toString());
    state = AsyncData(enabled);
  }
}
