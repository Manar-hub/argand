// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Argand';

  @override
  String get libraryEmptyTitle => 'No projects yet';

  @override
  String get libraryEmptyBody =>
      'Import a video or audio file to transcribe it on your device.';

  @override
  String get importAction => 'Import media';

  @override
  String get importCancelled => 'No file selected.';

  @override
  String get stagePreparingModel => 'Preparing model';

  @override
  String get stageCopyingMedia => 'Copying media';

  @override
  String get stageExtractingAudio => 'Extracting audio';

  @override
  String get stageTranscribing => 'Transcribing';

  @override
  String get stageSaving => 'Saving';

  @override
  String transcribingPercent(int percent) {
    return 'Transcribing… $percent%';
  }

  @override
  String get transcriptTitle => 'Transcript';

  @override
  String wordCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count words',
      one: '1 word',
      zero: 'No words',
    );
    return '$_temp0';
  }

  @override
  String speakerLabel(int number) {
    return 'Speaker $number';
  }

  @override
  String get transcriptEmpty => 'No speech was detected in this file.';

  @override
  String get playAction => 'Play';

  @override
  String get pauseAction => 'Pause';

  @override
  String get audioOnlyLabel => 'Audio only';

  @override
  String get playerUnavailable => 'This file can\'t be played back.';

  @override
  String get deleteAction => 'Delete';

  @override
  String get errorTitle => 'Something went wrong';

  @override
  String get transcriptionModelTitle => 'Transcription model';

  @override
  String get modelNameBase => 'Base';

  @override
  String get modelNameSmallQ51 => 'Small (quantized)';

  @override
  String get modelHintFaster => 'Faster, less accurate';

  @override
  String get modelHintAccurate => 'Slower, more accurate';

  @override
  String get stageIdentifyingSpeakers => 'Identifying speakers';

  @override
  String identifyingSpeakersPercent(int percent) {
    return 'Identifying speakers… $percent%';
  }

  @override
  String get retryAction => 'Try again';

  @override
  String get settingsMenuTooltip => 'Transcription settings';

  @override
  String get transcriptionLanguageTitle => 'Language';

  @override
  String get languageAuto => 'Detect automatically';

  @override
  String get languageAutoHint => 'The model identifies the language';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageEnglishHint => 'Skip detection, assume English';

  @override
  String get silenceSkippingTitle => 'Skip silence';

  @override
  String get silenceSkippingHint =>
      'Transcribe speech only. Faster, and avoids invented words over silence.';

  @override
  String get diarizationTitle => 'Identify speakers';

  @override
  String get diarizationHint =>
      'Label who is speaking. Slower, and skipped on very long recordings.';

  @override
  String get editModeEnable => 'Edit transcript';

  @override
  String get editModeDisable => 'Done editing';

  @override
  String get editModeHintLine =>
      'Tap a line to retype it, or a speaker name to reassign the turn.';

  @override
  String get editModeHintWord =>
      'Tap a word to retype it. Any change stays inside that word\'s own timing.';

  @override
  String get editScopeLine => 'Line';

  @override
  String get editScopeWord => 'Word';

  @override
  String get editScopeSpeakers => 'Speakers';

  @override
  String get editModeHintSpeakers =>
      'Pick a speaker, then tap the first word of the run.';

  @override
  String get editModeHintSpeakersAnchored =>
      'Now tap the last word, or the same word again for just that one.';

  @override
  String get renameSpeakerTitle => 'Name this speaker';

  @override
  String renameSpeakerHint(int number) {
    return 'Leave empty to go back to Speaker $number.';
  }

  @override
  String get renameSpeakerAction => 'Rename';

  @override
  String get reassignSpeakerTitle => 'Who is speaking?';

  @override
  String get editCancel => 'Cancel';

  @override
  String get editSave => 'Save';

  @override
  String get undoAction => 'Undo';

  @override
  String get redoAction => 'Redo';

  @override
  String get deleteProjectTitle => 'Delete this project?';

  @override
  String deleteProjectMessage(String size) {
    return 'This removes the video and its transcript from your device and frees $size. It cannot be undone.';
  }

  @override
  String projectSizeOnDisk(String duration, String size) {
    return '$duration · $size';
  }

  @override
  String sizeBytes(int count) {
    return '$count B';
  }

  @override
  String sizeKilobytes(int count) {
    return '$count KB';
  }

  @override
  String sizeMegabytes(int count) {
    return '$count MB';
  }

  @override
  String get projectsHeading => 'Projects';

  @override
  String get importHeadline => 'Transcribe';

  @override
  String get importSubhead => 'Video or audio — transcribed on your device';

  @override
  String get importEditHeadline => 'Import & edit';

  @override
  String get importEditSubhead =>
      'Transcribed automatically, then opens on the timeline';

  @override
  String projectCreated(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return '$dateString';
  }

  @override
  String get duplicateAction => 'Duplicate';

  @override
  String duplicateTitle(String title) {
    return '$title copy';
  }

  @override
  String get duplicateSharesMediaTitle => 'Duplicates share one file';

  @override
  String get duplicateSharesMediaBody =>
      'A copy reuses the same video and transcription, so it takes almost no extra space. Your edits stay separate. The video is only removed once every copy is deleted.';

  @override
  String get gotItAction => 'Got it';

  @override
  String get themeModeLabel => 'Appearance';

  @override
  String get themeModeLight => 'Light';

  @override
  String get themeModeDark => 'Dark';

  @override
  String get openAction => 'Open';

  @override
  String sizeGigabytes(String count) {
    return '$count GB';
  }

  @override
  String get exportAction => 'Export captions';

  @override
  String get exportSheetTitle => 'Export captions';

  @override
  String get exportSrt => 'SubRip (.srt)';

  @override
  String get exportSrtDetail =>
      'Works almost everywhere — players, editors, video sites';

  @override
  String get exportVtt => 'WebVTT (.vtt)';

  @override
  String get exportVttDetail =>
      'For the web, and keeps speaker names as voice tags';

  @override
  String get exportIncludeSpeakers => 'Include speaker names';

  @override
  String get exportRunning => 'Preparing captions…';

  @override
  String exportSaved(String fileName) {
    return 'Saved $fileName';
  }

  @override
  String get exportCancelled => 'Export cancelled.';

  @override
  String get exportFailed => 'Could not export captions.';

  @override
  String get exportEmpty => 'There are no captions to export yet.';

  @override
  String get editorModeScript => 'Script';

  @override
  String get editorModeTimeline => 'Timeline';

  @override
  String get timelineFullscreen => 'Fullscreen';

  @override
  String get timelineAspectToggle => 'Toggle fit';

  @override
  String get timelineMuteClip => 'Mute clip';

  @override
  String get timelineCover => 'Cover';

  @override
  String get timelineAddAudio => 'Add audio';

  @override
  String get timelineCaptionsLabel => 'Captions';

  @override
  String get timelineToolEdit => 'Edit';

  @override
  String get timelineToolAudio => 'Audio';

  @override
  String get timelineToolText => 'Text';

  @override
  String get timelineToolEffects => 'Effects';

  @override
  String get timelineToolOverlay => 'Overlay';

  @override
  String get timelineToolCaptions => 'Captions';

  @override
  String get timelineToolFilter => 'Filter';

  @override
  String timelineComingSoon(String feature) {
    return '$feature is coming soon.';
  }

  @override
  String get timelineNoClips => 'No media yet. Tap + to add a clip.';

  @override
  String get clipAdd => 'Add a clip';

  @override
  String get clipRemove => 'Remove';

  @override
  String get clipRemoveTitle => 'Remove this clip?';

  @override
  String get clipRemoveMessage =>
      'This deletes the clip\'s media from your device, along with anything transcribed from it. It cannot be undone.';

  @override
  String get clipMoveEarlier => 'Move earlier';

  @override
  String get clipMoveLater => 'Move later';

  @override
  String get clipTranscribe => 'Transcribe';

  @override
  String get clipNotTranscribed => 'Not transcribed yet.';

  @override
  String get clipNotTranscribedScript =>
      'This clip hasn\'t been transcribed yet. Switch to Timeline and tap Transcribe to start.';

  @override
  String get clipTranscribed => 'Transcribed.';

  @override
  String get clipTranscribeFailed => 'Couldn\'t transcribe this clip.';

  @override
  String get createProjectHeadline => 'Create project';

  @override
  String get createProjectSubhead => 'Name it, then add clips on the timeline';

  @override
  String get createProjectTitle => 'Name this project';

  @override
  String get createProjectAction => 'Create';

  @override
  String get createProjectDefaultName => 'Untitled project';

  @override
  String get layerAdd => 'Add layer';

  @override
  String get layerRemove => 'Remove layer';

  @override
  String get layerHint => 'Add a layer to mark what to transcribe.';

  @override
  String get layerSelected => 'Layer selected.';

  @override
  String get layerNoRoom => 'No room for another layer here.';

  @override
  String get trackShow => 'Show track';

  @override
  String get trackHide => 'Hide track';

  @override
  String get trackReorder => 'Reorder tracks';
}
