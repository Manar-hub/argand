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
  String get transcriptionModelTitle => 'Model';

  @override
  String get modelNameBase => 'Base';

  @override
  String get modelNameSmallQ51 => 'Small (quantized)';

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
  String get languageEnglish => 'English';

  @override
  String get silenceSkippingTitle => 'Skip silence';

  @override
  String get silenceSkippingHint =>
      'Faster when there are pauses. Can be slower on non-stop speech.';

  @override
  String get diarizationTitle => 'Identify speakers';

  @override
  String get diarizationHint => 'Slower. Skipped on very long recordings.';

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
  String get librarySearchHint => 'Search projects and words';

  @override
  String get librarySearchClear => 'Clear search';

  @override
  String get selectionRemove => 'Remove';

  @override
  String get audioSelected => 'Sound selected.';

  @override
  String get audioRestore => 'Restore';

  @override
  String get translateAction => 'Translate';

  @override
  String get translateTitle => 'Translate to';

  @override
  String get translatePackSize => 'About 30 MB, downloaded once';

  @override
  String get translateDownloading => 'Downloading…';

  @override
  String get translateDeletePack => 'Delete download';

  @override
  String get translateRemove => 'Remove translation';

  @override
  String get translateOff => 'Off';

  @override
  String get translateWorking => 'Translating…';

  @override
  String translateDone(String language) {
    return 'Translated to $language';
  }

  @override
  String get translateUnsupported =>
      'This transcript\'s language can\'t be translated yet.';

  @override
  String get translateDownloadFailed =>
      'Couldn\'t download the language. Check your connection and try again.';

  @override
  String get translateFailed => 'Translation failed. Try again.';

  @override
  String get translateToOption => 'Translate to';

  @override
  String get showTranslation => 'Show translation';

  @override
  String get translationAdd => 'Add translation';

  @override
  String get exportIncludeTranslation => 'Include translation';

  @override
  String get librarySearchEmpty => 'No project names or words match.';

  @override
  String get importHeadline => 'Transcribe';

  @override
  String get importSubhead => 'Video or audio — transcribed on your device';

  @override
  String projectCreated(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return '$dateString';
  }

  @override
  String get duplicateAction => 'Duplicate';

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
  String sizeGigabytes(String count) {
    return '$count GB';
  }

  @override
  String get exportAction => 'Export';

  @override
  String get exportSheetTitle => 'Export';

  @override
  String get exportSrtDetail =>
      'Works almost everywhere — players, editors, video sites';

  @override
  String get exportVttDetail =>
      'For the web, and keeps speaker names as voice tags';

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
  String get trackKindImageDetail =>
      'A picture over the video, at the playhead.';

  @override
  String get translationSelected => 'Translation line selected.';

  @override
  String get imageSelected => 'Image selected.';

  @override
  String get trackKindVideo => 'Video';

  @override
  String get trackKindUnavailable =>
      'Needs export compositing, which isn\'t built yet.';

  @override
  String get timelineToolZoom => 'Zoom';

  @override
  String get timelineToolRotate => 'Rotate';

  @override
  String selectionCount(int count) {
    return '$count selected';
  }

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
  String get timelineToolText => 'Text';

  @override
  String timelineComingSoon(String feature) {
    return '$feature is coming soon.';
  }

  @override
  String get timelineNoClips => 'No media yet. Tap + to add a clip.';

  @override
  String get clipAdd => 'Add a clip';

  @override
  String get clipTranscribe => 'Transcribe';

  @override
  String get clipNotTranscribedScript =>
      'This clip hasn\'t been transcribed yet. Switch to Timeline and tap Transcribe to start.';

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
  String get layerRerunBody =>
      'The words this layer produced will be replaced. Any corrections you typed and any speaker names you set on them are lost.';

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
  String get exportProFormatPremiereDetail =>
      'Captions as text clips on a video track';

  @override
  String get exportProName => 'Argand Pro';

  @override
  String get exportProPitch => 'One payment. No watermark, no ads.';

  @override
  String get exportGetPro => 'Get Pro';

  @override
  String get adPlaceholderLabel => 'Test ad';

  @override
  String get adPlaceholderBody =>
      'Shown when the ad network has nothing to play. Watch to the end to export this video without the watermark, or get Pro to skip ads for good.';

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
  String get videoSettingsWatermarkPreview => 'Watermark preview';

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
  String get settingsModels => 'Transcription models';

  @override
  String get settingsModelsDetail => 'Add, remove and choose on-device models';

  @override
  String get settingsLanguages => 'Translation languages';

  @override
  String get settingsLanguagesDetail => 'Download or remove language packs';

  @override
  String get languagesNote =>
      'Each language is a pack of about 30 MB, downloaded once. Text is always translated on this device.';

  @override
  String get packAdd => 'Add';

  @override
  String get packRemove => 'Remove';

  @override
  String get packBuiltIn => 'Built in';

  @override
  String get packInstalled => 'Downloaded';

  @override
  String get packNotInstalled => 'Not downloaded';

  @override
  String get packWaiting => 'Waiting…';

  @override
  String get packInstalling => 'Installing…';

  @override
  String get packFailed => 'Couldn\'t download. Try again.';

  @override
  String get modelNotLoadable => 'Not a Whisper model this app can run';

  @override
  String packRemoveTitle(String name) {
    return 'Remove $name?';
  }

  @override
  String get packRemoveBody =>
      'It frees the space it takes, and can be added again at any time.';

  @override
  String packDownloading(int percent) {
    return 'Downloading $percent%';
  }

  @override
  String packMegabytes(String size) {
    return '$size MB';
  }

  @override
  String modelReady(String details) {
    return 'Ready · $details';
  }

  @override
  String modelLayers(int count) {
    return '$count layers';
  }

  @override
  String get packDownloadingUnknown => 'Downloading…';

  @override
  String get proBuyLoading => 'Getting the price…';

  @override
  String get proUnavailable =>
      'The store can\'t be reached right now. Check your connection.';

  @override
  String get proRetry => 'Try again';

  @override
  String get proRestoreNone => 'No Pro purchase was found to restore.';

  @override
  String get proOffline =>
      'No connection to the store. Try again when you\'re online.';

  @override
  String get proFailed => 'The purchase didn\'t go through. Please try again.';

  @override
  String get modelsNoteShort =>
      'Larger models are more accurate but consume more resources.';

  @override
  String get packDownload => 'Download';

  @override
  String get packDownloadModelBody =>
      'It\'s saved on this device and can be removed at any time.';

  @override
  String get packDownloadLanguageBody => 'About 30 MB, downloaded once.';

  @override
  String packDownloadTitle(String name) {
    return 'Download $name?';
  }

  @override
  String get proNotOnSale => 'Pro isn\'t on sale yet. Please check back soon.';

  @override
  String get proHeroBadge => 'One-time · No subscription';

  @override
  String get proHeadline => 'Pay once.\nKeep Argand yours.';

  @override
  String get proLede =>
      'Transcription and editing stay free. This removes the extras and keeps the app going.';

  @override
  String get proSupportTitle => 'Support the developer';

  @override
  String get proSupportDetail => 'Funds fixes, updates and new features';

  @override
  String get proNoAdsTitle => 'No ads';

  @override
  String get proNoAdsDetail => 'Nothing between you and your edit';

  @override
  String get proNoWatermarkTitle => 'No watermark';

  @override
  String get proNoWatermarkDetail => 'Clean exports, every time';

  @override
  String get proOnce => 'once';

  @override
  String get proForGood => 'Yours for good.\nNo renewals.';

  @override
  String get proFinePrint =>
      'One-time purchase, charged to your Google Play account.';

  @override
  String get proRestoreShort => 'Restore';

  @override
  String get proThanksBadge => 'Supporter';

  @override
  String get proThanksTitle => 'Thank you.';

  @override
  String get proThanksBody =>
      'You\'re helping keep Argand independent. The extras are gone for good.';

  @override
  String get proThanksAds => 'Ads removed';

  @override
  String get proThanksWatermark => 'Watermark removed from exports';

  @override
  String get proThanksRestore => 'Restore anytime on a new device';

  @override
  String get proThanksBack => 'Back to projects';

  @override
  String proUnlock(String price) {
    return 'Unlock for $price';
  }

  @override
  String get proResetTitle => 'Reset Pro for testing?';

  @override
  String get proResetBody =>
      'Starts over as a new test customer, so Pro is off until it\'s bought again. Test Store purchases are simulated and cost nothing.';

  @override
  String get proResetAction => 'Reset Pro';

  @override
  String get proResetDone => 'Pro is off. Ready for another take.';

  @override
  String get proResetFailed =>
      'Couldn\'t reset Pro. Check the connection and try again.';

  @override
  String get transcriptionMoreModels => 'Manage models';

  @override
  String get styleScopeSpeaker => 'Per speaker';

  @override
  String get styleScopeAllTranslations => 'All translations';

  @override
  String get editSpeakerTitle => 'Edit speaker';

  @override
  String get speakerColor => 'Colour';

  @override
  String get showSpeakerNamesOnVideo => 'Show names on video';

  @override
  String get showSpeakerNamesOnVideoDetail =>
      'Each caption shows who is speaking';

  @override
  String get exportAss => 'Export ASS';

  @override
  String get exportProLocked => 'Pro';

  @override
  String get supporterTitle => 'Argand supporter';

  @override
  String get supporterDetail => 'Thank you for backing Argand';

  @override
  String get videoSettingsPreviewItem => 'Preview';

  @override
  String get videoSettingsSafeZonePreview => 'Safe-zone preview';

  @override
  String get exportProFormatTtml => 'TTML';

  @override
  String get exportProFormatTtmlDetail =>
      'Timed text for broadcast/streaming, with speaker colours';

  @override
  String get exportTtml => 'Export TTML';

  @override
  String get exportFcpxml => 'Export FCPXML';

  @override
  String get exportPremiereXml => 'Export XML';

  @override
  String get settingsAccentColorPreview => 'Action colour preview';

  @override
  String get settingsProFeature => 'Pro feature';

  @override
  String get transcribeNameTitle => 'Project name';

  @override
  String get transcribeNameHint => 'Named after the file';

  @override
  String get renameProjectTitle => 'Rename project';

  @override
  String get renameProjectAction => 'Rename';

  @override
  String get proExportsTitle => 'Pro exports';

  @override
  String get proExportsDetail => 'Take your captions into any editor';

  @override
  String get proFontsTitle => 'Custom fonts and themes';

  @override
  String get proFontsDetail => 'Your own typefaces, your own colours';

  @override
  String get proThanksExports => 'Pro exports unlocked';

  @override
  String get proThanksFonts => 'Custom fonts and themes unlocked';

  @override
  String get fontSearchCell => 'Search';

  @override
  String get fontSearchTitle => 'Fonts';

  @override
  String get fontSearchHint => 'Search fonts';

  @override
  String get fontSearchAdd => 'Add custom font';

  @override
  String get fontSearchAdding => 'Adding…';

  @override
  String get fontSearchNotAFont =>
      'That file isn\'t a font. Choose a .ttf or .otf file.';

  @override
  String get fontSearchNone => 'No fonts match';
}
