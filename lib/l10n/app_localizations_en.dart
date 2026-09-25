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
  String get settingsAccentColor => 'Action colour';

  @override
  String get openAction => 'Open';

  @override
  String sizeGigabytes(String count) {
    return '$count GB';
  }

  @override
  String get exportAction => 'Export';

  @override
  String get exportSheetTitle => 'Export';

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
  String get exportVideoDetail =>
      'Renders the timeline and saves it to Downloads';

  @override
  String exportVideoRunning(int percent) {
    return 'Rendering video… $percent%';
  }

  @override
  String get exportVideoStarting => 'Rendering video…';

  @override
  String exportVideoSaved(String fileName) {
    return 'Saved to Downloads: $fileName';
  }

  @override
  String get exportVideoFailed => 'Could not render the video.';

  @override
  String get exportVideoEmpty =>
      'There is nothing on the timeline to render yet.';

  @override
  String get transcribeOptionsTitle => 'Transcribe';

  @override
  String get transcribeOptionsConfirm => 'Transcribe';

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
  String get timelineMuteClip => 'Mute clip';

  @override
  String get timelineCover => 'Cover';

  @override
  String get trackAdd => 'Add track';

  @override
  String get trackAddTitle => 'Add a track';

  @override
  String get trackKindTranscribe => 'Transcribe';

  @override
  String get trackKindTranscribeDetail =>
      'Mark stretches of the timeline to transcribe.';

  @override
  String get trackKindAudio => 'Audio';

  @override
  String get trackKindTextDetail => 'Words on the picture, at the playhead.';

  @override
  String zoomPercent(int percent) {
    return '$percent%';
  }

  @override
  String get trackKindText => 'Text';

  @override
  String get trackKindImage => 'Image';

  @override
  String get trackKindVideo => 'Video';

  @override
  String get trackKindUnavailable =>
      'Needs export compositing, which isn\'t built yet.';

  @override
  String get timelineCaptionsLabel => 'Captions';

  @override
  String get timelineToolZoom => 'Zoom';

  @override
  String get timelineToolRotate => 'Rotate';

  @override
  String selectionCount(int count) {
    return '$count selected';
  }

  @override
  String get selectionDelete => 'Delete';

  @override
  String get selectionDone => 'Done';

  @override
  String get selectionHint => 'Tap to edit · hold to select several';

  @override
  String get textSelected => 'Text selected.';

  @override
  String get textEdit => 'Edit text';

  @override
  String get sentenceSelected => 'Sentence selected.';

  @override
  String get textPlaceholder => 'Text';

  @override
  String get clipSelected => 'Clip selected.';

  @override
  String clipRemoveManyTitle(int count) {
    return 'Remove $count clips?';
  }

  @override
  String get timelineToolStyle => 'Style';

  @override
  String get styleFont => 'Font';

  @override
  String get styleColor => 'Colour';

  @override
  String get styleCaption => 'Animation';

  @override
  String get styleHighlight => 'Highlight';

  @override
  String get styleScopeAll => 'All captions';

  @override
  String get styleNothing => 'Select a text or caption to style it.';

  @override
  String get styleColorSpeaker => 'Speaker';

  @override
  String get styleColorDefault => 'Default';

  @override
  String get styleModeStandard => 'Standard';

  @override
  String get styleModeKaraoke => 'Karaoke';

  @override
  String get styleModeWordByWord => 'Word';

  @override
  String get styleModeHighlight => 'Highlight';

  @override
  String get styleHighlightBox => 'Box';

  @override
  String get styleHighlightLetters => 'Letters';

  @override
  String styleScopeSelected(int count) {
    return 'Selected ($count)';
  }

  @override
  String get styleShadow => 'Shadow';

  @override
  String get styleShadowNone => 'None';

  @override
  String get styleShadowOnBackground => 'Words on a background have no shadow.';

  @override
  String get styleColorText => 'Text';

  @override
  String get styleColorBackground => 'Background';

  @override
  String get styleColorNone => 'None';

  @override
  String get styleHue => 'Hue';

  @override
  String get styleShade => 'Shade';

  @override
  String get timelineToolSplit => 'Split';

  @override
  String get splitTooClose => 'Too close to the edge of the clip to split.';

  @override
  String get splitNothingSelected =>
      'Select something on the timeline to split.';

  @override
  String get splitNotUnderPlayhead =>
      'The playhead is not over anything selected.';

  @override
  String get splitDone => 'Clip split.';

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
  String get layerRerunTitle => 'Transcribe this layer again?';

  @override
  String get layerRerunBody =>
      'The words this layer produced will be replaced. Any corrections you typed and any speaker names you set on them are lost.';

  @override
  String get layerRerunConfirm => 'Transcribe again';

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

  @override
  String get exportOptionsQuality => 'Resolution';

  @override
  String get exportOptionsAspect => 'Aspect ratio';

  @override
  String get exportQuality720 => '720p';

  @override
  String get exportQuality1080 => '1080p';

  @override
  String get exportQuality1440 => '2K';

  @override
  String get exportQuality2160 => '4K';

  @override
  String get exportQualitySource => 'Source';

  @override
  String get exportAspectSource => 'Source';

  @override
  String get exportAspectPortrait => '9:16';

  @override
  String get exportAspectSquare => '1:1';

  @override
  String get exportAspectFeed => '4:5';

  @override
  String get exportAspectWide => '16:9';

  @override
  String exportFrameSize(int width, int height) {
    return '$width x $height';
  }

  @override
  String get exportRemoveWatermark => 'Remove watermark';

  @override
  String get exportRemoveWatermarkDetail => 'Watch a short ad first';

  @override
  String get exportStart => 'Export';

  @override
  String get exportProgressTitle => 'Rendering video';

  @override
  String get exportProgressPreparing => 'Preparing...';

  @override
  String exportProgressPercent(int percent) {
    return '$percent%';
  }

  @override
  String get exportProgressNote => 'Keep the app open while this finishes.';

  @override
  String get exportCancel => 'Cancel export';

  @override
  String get exportTabVideo => 'Video';

  @override
  String get exportTabSrt => 'SRT';

  @override
  String get exportTabVtt => 'VTT';

  @override
  String get exportTabPro => 'Pro formats';

  @override
  String get exportWatchAdThenExport => 'Watch ad, then export';

  @override
  String get exportAdOffline =>
      'Couldn\'t load the ad — the watermark stays on.';

  @override
  String get exportAdIncomplete =>
      'Watch the ad to the end to remove the watermark.';

  @override
  String get exportProIncluded => 'No watermark — included with Pro';

  @override
  String get exportLineLength => 'Line length';

  @override
  String get exportLineStandard => 'Standard';

  @override
  String get exportLineShort => 'Short';

  @override
  String get exportLineHint => 'Short lines suit vertical video.';

  @override
  String get exportSubtitlesTimed =>
      'Timed to the whole timeline, so it lines up with the exported video.';

  @override
  String get exportSubtitlesNeedTranscript =>
      'Transcribe something first — there are no captions to export yet.';

  @override
  String get exportProFormatsIntro => 'Formats for professional editing tools.';

  @override
  String get exportProFormatAss => 'ASS / SSA';

  @override
  String get exportProFormatAssDetail =>
      'Styled subtitles with speaker colours';

  @override
  String get exportProFormatFcpxml => 'Final Cut Pro (FCPXML)';

  @override
  String get exportProFormatFcpxmlDetail =>
      'Captions as titles on your timeline';

  @override
  String get exportProFormatPremiere => 'Premiere Pro (XML)';

  @override
  String get exportProFormatPremiereDetail => 'Captions as a caption track';

  @override
  String get exportProComing => 'Coming with Pro';

  @override
  String get exportProName => 'Argand Pro';

  @override
  String get exportProPitch => 'One payment. No watermark, no ads.';

  @override
  String get exportGetPro => 'Get Pro';

  @override
  String get exportProSoon => 'Purchases aren\'t connected yet.';

  @override
  String get adPlaceholderLabel => 'Ad placeholder';

  @override
  String get adPlaceholderBody =>
      'A rewarded ad plays here once ads are connected.';

  @override
  String get adPlaceholderContinue => 'Continue to export';

  @override
  String get adPlaceholderClose => 'Close ad';

  @override
  String adPlaceholderSeconds(int seconds) {
    return '$seconds';
  }

  @override
  String get videoSettingsOpen => 'Video settings';

  @override
  String get videoSettingsVisible => 'Visible';

  @override
  String get videoSettingsHidden => 'Hidden';

  @override
  String get videoSettingsWatermarkPreview => 'Preview';

  @override
  String get watermarkTopLeft => 'Upper left';

  @override
  String get watermarkTopRight => 'Upper right';

  @override
  String get watermarkBottomLeft => 'Lower left';

  @override
  String get watermarkBottomRight => 'Lower right';

  @override
  String get videoSettingsClose => 'Close video settings';

  @override
  String get videoSettingsWatermarkItem => 'Watermark';
}
