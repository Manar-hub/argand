import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// Application name, shown in the library app bar
  ///
  /// In en, this message translates to:
  /// **'Argand'**
  String get appTitle;

  /// Headline on the empty library screen
  ///
  /// In en, this message translates to:
  /// **'No projects yet'**
  String get libraryEmptyTitle;

  /// Supporting text on the empty library screen
  ///
  /// In en, this message translates to:
  /// **'Import a video or audio file to transcribe it on your device.'**
  String get libraryEmptyBody;

  /// Label of the button that opens the file picker
  ///
  /// In en, this message translates to:
  /// **'Import media'**
  String get importAction;

  /// Shown when the user dismisses the file picker
  ///
  /// In en, this message translates to:
  /// **'No file selected.'**
  String get importCancelled;

  /// Pipeline stage: copying the model into place
  ///
  /// In en, this message translates to:
  /// **'Preparing model'**
  String get stagePreparingModel;

  /// Pipeline stage: copying the picked file into app storage
  ///
  /// In en, this message translates to:
  /// **'Copying media'**
  String get stageCopyingMedia;

  /// Pipeline stage: decoding to 16kHz mono WAV
  ///
  /// In en, this message translates to:
  /// **'Extracting audio'**
  String get stageExtractingAudio;

  /// Pipeline stage: running speech recognition
  ///
  /// In en, this message translates to:
  /// **'Transcribing'**
  String get stageTranscribing;

  /// Pipeline stage: writing results to the database
  ///
  /// In en, this message translates to:
  /// **'Saving'**
  String get stageSaving;

  /// Transcription stage with a known completion percentage
  ///
  /// In en, this message translates to:
  /// **'Transcribing… {percent}%'**
  String transcribingPercent(int percent);

  /// Header above the word list on the project screen
  ///
  /// In en, this message translates to:
  /// **'Transcript'**
  String get transcriptTitle;

  /// Number of transcribed words in a transcript
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No words} =1{1 word} other{{count} words}}'**
  String wordCount(int count);

  /// Heading above a run of words attributed to one speaker. Numbered from 1 because the engine's own indices start at 0.
  ///
  /// In en, this message translates to:
  /// **'Speaker {number}'**
  String speakerLabel(int number);

  /// Shown when transcription produced no words
  ///
  /// In en, this message translates to:
  /// **'No speech was detected in this file.'**
  String get transcriptEmpty;

  /// Button that starts media playback
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get playAction;

  /// Button that pauses media playback
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pauseAction;

  /// Placeholder shown when the media has no video track
  ///
  /// In en, this message translates to:
  /// **'Audio only'**
  String get audioOnlyLabel;

  /// Shown when the media player fails to load the file
  ///
  /// In en, this message translates to:
  /// **'This file can\'t be played back.'**
  String get playerUnavailable;

  /// Menu entry that opens the delete-project confirmation
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteAction;

  /// Headline shown when the import pipeline fails
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get errorTitle;

  /// Header of the menu that selects which Whisper model transcribes
  ///
  /// In en, this message translates to:
  /// **'Transcription model'**
  String get transcriptionModelTitle;

  /// Display name of the bundled base Whisper model
  ///
  /// In en, this message translates to:
  /// **'Base'**
  String get modelNameBase;

  /// Display name of the bundled small-q5_1 Whisper model
  ///
  /// In en, this message translates to:
  /// **'Small (quantized)'**
  String get modelNameSmallQ51;

  /// Subtitle describing the smaller, quicker model
  ///
  /// In en, this message translates to:
  /// **'Faster, less accurate'**
  String get modelHintFaster;

  /// Subtitle describing the larger, more accurate model
  ///
  /// In en, this message translates to:
  /// **'Slower, more accurate'**
  String get modelHintAccurate;

  /// Pipeline stage: running speaker diarization over the extracted audio
  ///
  /// In en, this message translates to:
  /// **'Identifying speakers'**
  String get stageIdentifyingSpeakers;

  /// Diarization stage with a known completion percentage
  ///
  /// In en, this message translates to:
  /// **'Identifying speakers… {percent}%'**
  String identifyingSpeakersPercent(int percent);

  /// Button that retries a failed operation
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get retryAction;

  /// Tooltip on the app-bar button that opens transcription settings
  ///
  /// In en, this message translates to:
  /// **'Transcription settings'**
  String get settingsMenuTooltip;

  /// Header of the menu section that selects the spoken language of the media
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get transcriptionLanguageTitle;

  /// Language option letting the engine identify the spoken language itself
  ///
  /// In en, this message translates to:
  /// **'Detect automatically'**
  String get languageAuto;

  /// Subtitle for the automatic language-detection option
  ///
  /// In en, this message translates to:
  /// **'The model identifies the language'**
  String get languageAutoHint;

  /// Language option pinning transcription to English
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// Subtitle for the pinned-English language option
  ///
  /// In en, this message translates to:
  /// **'Skip detection, assume English'**
  String get languageEnglishHint;

  /// Header of the settings section toggling voice activity detection
  ///
  /// In en, this message translates to:
  /// **'Skip silence'**
  String get silenceSkippingTitle;

  /// Subtitle explaining what the silence-skipping toggle does
  ///
  /// In en, this message translates to:
  /// **'Transcribe speech only. Faster, and avoids invented words over silence.'**
  String get silenceSkippingHint;

  /// Header of the settings section toggling speaker diarization
  ///
  /// In en, this message translates to:
  /// **'Identify speakers'**
  String get diarizationTitle;

  /// Subtitle explaining what the speaker-identification toggle does
  ///
  /// In en, this message translates to:
  /// **'Label who is speaking. Slower, and skipped on very long recordings.'**
  String get diarizationHint;

  /// Tooltip on the app bar control that switches the transcript from playback into editing
  ///
  /// In en, this message translates to:
  /// **'Edit transcript'**
  String get editModeEnable;

  /// Tooltip on the app bar control that leaves transcript editing
  ///
  /// In en, this message translates to:
  /// **'Done editing'**
  String get editModeDisable;

  /// Banner shown in edit mode when a tap opens the whole sentence
  ///
  /// In en, this message translates to:
  /// **'Tap a line to retype it, or a speaker name to reassign the turn.'**
  String get editModeHintLine;

  /// Banner shown in edit mode when a tap opens a single word, noting that this is the more precise option
  ///
  /// In en, this message translates to:
  /// **'Tap a word to retype it. Any change stays inside that word\'s own timing.'**
  String get editModeHintWord;

  /// Label of the control that makes a tap open the whole sentence
  ///
  /// In en, this message translates to:
  /// **'Line'**
  String get editScopeLine;

  /// Label of the control that makes a tap open a single word
  ///
  /// In en, this message translates to:
  /// **'Word'**
  String get editScopeWord;

  /// Label of the control that makes a tap assign a speaker to words instead of editing text
  ///
  /// In en, this message translates to:
  /// **'Speakers'**
  String get editScopeSpeakers;

  /// Banner shown in speaker-assignment mode before any word has been chosen
  ///
  /// In en, this message translates to:
  /// **'Pick a speaker, then tap the first word of the run.'**
  String get editModeHintSpeakers;

  /// Banner shown once the first word of a speaker range has been chosen
  ///
  /// In en, this message translates to:
  /// **'Now tap the last word, or the same word again for just that one.'**
  String get editModeHintSpeakersAnchored;

  /// Header of the field for giving a speaker a custom name
  ///
  /// In en, this message translates to:
  /// **'Name this speaker'**
  String get renameSpeakerTitle;

  /// Note under the rename field explaining that clearing it restores the numbered default
  ///
  /// In en, this message translates to:
  /// **'Leave empty to go back to Speaker {number}.'**
  String renameSpeakerHint(int number);

  /// Tooltip on the control that renames a speaker
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get renameSpeakerAction;

  /// Header of the sheet listing speakers to reassign a turn to
  ///
  /// In en, this message translates to:
  /// **'Who is speaking?'**
  String get reassignSpeakerTitle;

  /// Dismisses an edit without applying it
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get editCancel;

  /// Applies an edit
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get editSave;

  /// Tooltip on the app bar control that reverses the last transcript edit
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undoAction;

  /// Tooltip on the app bar control that re-applies an undone transcript edit
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get redoAction;

  /// Heading of the dialog confirming permanent deletion of a project
  ///
  /// In en, this message translates to:
  /// **'Delete this project?'**
  String get deleteProjectTitle;

  /// Body of the delete-project confirmation, stating plainly that deletion is permanent and how much space it recovers
  ///
  /// In en, this message translates to:
  /// **'This removes the video and its transcript from your device and frees {size}. It cannot be undone.'**
  String deleteProjectMessage(String size);

  /// Library row subtitle pairing a project's running time with the space it occupies
  ///
  /// In en, this message translates to:
  /// **'{duration} · {size}'**
  String projectSizeOnDisk(String duration, String size);

  /// A file size below one kilobyte
  ///
  /// In en, this message translates to:
  /// **'{count} B'**
  String sizeBytes(int count);

  /// A file size in kilobytes
  ///
  /// In en, this message translates to:
  /// **'{count} KB'**
  String sizeKilobytes(int count);

  /// A file size in megabytes
  ///
  /// In en, this message translates to:
  /// **'{count} MB'**
  String sizeMegabytes(int count);

  /// Heading above the list of imported projects in the library
  ///
  /// In en, this message translates to:
  /// **'Projects'**
  String get projectsHeading;

  /// Label on the library's transcribe-only entry panel; opens the resulting project in Script mode
  ///
  /// In en, this message translates to:
  /// **'Transcribe'**
  String get importHeadline;

  /// Supporting line under the transcribe entry panel, saying what can be imported and that nothing is uploaded
  ///
  /// In en, this message translates to:
  /// **'Video or audio — transcribed on your device'**
  String get importSubhead;

  /// Label on the library's import-and-edit entry panel; opens the resulting project in Timeline mode
  ///
  /// In en, this message translates to:
  /// **'Import & edit'**
  String get importEditHeadline;

  /// Supporting line under the import-and-edit entry panel
  ///
  /// In en, this message translates to:
  /// **'Transcribed automatically, then opens on the timeline'**
  String get importEditSubhead;

  /// When a project was imported, shown in its library row
  ///
  /// In en, this message translates to:
  /// **'{date}'**
  String projectCreated(DateTime date);

  /// Menu entry that copies a project so a second edit can diverge from it
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get duplicateAction;

  /// Title given to a duplicated project
  ///
  /// In en, this message translates to:
  /// **'{title} copy'**
  String duplicateTitle(String title);

  /// Heading of the one-time notice explaining how duplicating works
  ///
  /// In en, this message translates to:
  /// **'Duplicates share one file'**
  String get duplicateSharesMediaTitle;

  /// Body of the one-time notice explaining that duplicates share media and cost no storage
  ///
  /// In en, this message translates to:
  /// **'A copy reuses the same video and transcription, so it takes almost no extra space. Your edits stay separate. The video is only removed once every copy is deleted.'**
  String get duplicateSharesMediaBody;

  /// Dismisses an informational notice
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get gotItAction;

  /// Heading of the light/dark theme control in settings
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get themeModeLabel;

  /// Theme option that forces the light theme
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeModeLight;

  /// Theme option that forces the dark theme
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeModeDark;

  /// Menu entry that opens a project
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get openAction;

  /// A file size in gigabytes, shown with one decimal place
  ///
  /// In en, this message translates to:
  /// **'{count} GB'**
  String sizeGigabytes(String count);

  /// Tooltip on the app bar control that opens the export options
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get exportAction;

  /// Header of the sheet listing what can be exported
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get exportSheetTitle;

  /// Menu entry exporting captions as a SubRip subtitle file
  ///
  /// In en, this message translates to:
  /// **'SubRip (.srt)'**
  String get exportSrt;

  /// Explains where a SubRip file can be used
  ///
  /// In en, this message translates to:
  /// **'Works almost everywhere — players, editors, video sites'**
  String get exportSrtDetail;

  /// Menu entry exporting captions as a WebVTT subtitle file
  ///
  /// In en, this message translates to:
  /// **'WebVTT (.vtt)'**
  String get exportVtt;

  /// Explains where a WebVTT file can be used and what it preserves
  ///
  /// In en, this message translates to:
  /// **'For the web, and keeps speaker names as voice tags'**
  String get exportVttDetail;

  /// Menu entry rendering the project's clips into a single video file
  ///
  /// In en, this message translates to:
  /// **'Video (.mp4)'**
  String get exportVideo;

  /// Explains what the video export produces
  ///
  /// In en, this message translates to:
  /// **'Renders the timeline and saves it to Downloads'**
  String get exportVideoDetail;

  /// Progress message shown while the video is being rendered
  ///
  /// In en, this message translates to:
  /// **'Rendering video… {percent}%'**
  String exportVideoRunning(int percent);

  /// Progress message shown before the renderer reports a percentage
  ///
  /// In en, this message translates to:
  /// **'Rendering video…'**
  String get exportVideoStarting;

  /// Confirmation shown when the rendered video has been written
  ///
  /// In en, this message translates to:
  /// **'Saved to Downloads: {fileName}'**
  String exportVideoSaved(String fileName);

  /// Shown when rendering the video did not produce a file
  ///
  /// In en, this message translates to:
  /// **'Could not render the video.'**
  String get exportVideoFailed;

  /// Shown when a video export is asked for but the project has no usable clips
  ///
  /// In en, this message translates to:
  /// **'There is nothing on the timeline to render yet.'**
  String get exportVideoEmpty;

  /// Reason shown on the disabled subtitle export entries when the clip has no transcript yet
  ///
  /// In en, this message translates to:
  /// **'Transcribe this clip first'**
  String get exportNeedsTranscript;

  /// Title of the dialog that collects transcription choices before a run starts
  ///
  /// In en, this message translates to:
  /// **'Transcribe'**
  String get transcribeOptionsTitle;

  /// Button that starts the transcription with the chosen options
  ///
  /// In en, this message translates to:
  /// **'Transcribe'**
  String get transcribeOptionsConfirm;

  /// Toggle controlling whether exported captions are attributed to speakers
  ///
  /// In en, this message translates to:
  /// **'Include speaker names'**
  String get exportIncludeSpeakers;

  /// Shown while the caption file is being written
  ///
  /// In en, this message translates to:
  /// **'Preparing captions…'**
  String get exportRunning;

  /// Confirmation after a caption file is written to the location the user chose
  ///
  /// In en, this message translates to:
  /// **'Saved {fileName}'**
  String exportSaved(String fileName);

  /// Shown when the user dismisses the system save dialog
  ///
  /// In en, this message translates to:
  /// **'Export cancelled.'**
  String get exportCancelled;

  /// Shown when writing the caption file failed
  ///
  /// In en, this message translates to:
  /// **'Could not export captions.'**
  String get exportFailed;

  /// Shown when export is attempted on a transcript with no words
  ///
  /// In en, this message translates to:
  /// **'There are no captions to export yet.'**
  String get exportEmpty;

  /// Label of the mode switch segment that shows the transcript-first editing view
  ///
  /// In en, this message translates to:
  /// **'Script'**
  String get editorModeScript;

  /// Label of the mode switch segment that shows the clip/track editing view
  ///
  /// In en, this message translates to:
  /// **'Timeline'**
  String get editorModeTimeline;

  /// Tooltip on the button that opens the video preview full screen
  ///
  /// In en, this message translates to:
  /// **'Fullscreen'**
  String get timelineFullscreen;

  /// Tooltip on the button that switches the preview between fitted and filled framing
  ///
  /// In en, this message translates to:
  /// **'Toggle fit'**
  String get timelineAspectToggle;

  /// Label under the track icon that mutes the video's own audio
  ///
  /// In en, this message translates to:
  /// **'Mute clip'**
  String get timelineMuteClip;

  /// Label under the track icon that sets the project's cover frame
  ///
  /// In en, this message translates to:
  /// **'Cover'**
  String get timelineCover;

  /// Button below the timeline that adds a new track to the stack
  ///
  /// In en, this message translates to:
  /// **'Add track'**
  String get trackAdd;

  /// Heading of the sheet listing the kinds of track that can be added
  ///
  /// In en, this message translates to:
  /// **'Add a track'**
  String get trackAddTitle;

  /// Track kind: a lane of ranges marked for transcription
  ///
  /// In en, this message translates to:
  /// **'Transcribe'**
  String get trackKindTranscribe;

  /// Explanation under the Transcribe track kind
  ///
  /// In en, this message translates to:
  /// **'Mark stretches of the timeline to transcribe.'**
  String get trackKindTranscribeDetail;

  /// Track kind: an imported audio file, e.g. music or voiceover
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get trackKindAudio;

  /// Track kind: text overlaid on the video
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get trackKindText;

  /// Track kind: an image overlaid on the video
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get trackKindImage;

  /// Track kind: a video overlaid on the main one
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get trackKindVideo;

  /// Explanation under the track kinds that cannot be added yet, stating what is missing rather than only that they are disabled
  ///
  /// In en, this message translates to:
  /// **'Needs export compositing, which isn\'t built yet.'**
  String get trackKindUnavailable;

  /// Heading above the caption list shown when the Captions toolbar button is toggled on
  ///
  /// In en, this message translates to:
  /// **'Captions'**
  String get timelineCaptionsLabel;

  /// Bottom toolbar button: cut/trim/split (not yet built)
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get timelineToolEdit;

  /// Bottom toolbar button: audio tools (not yet built)
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get timelineToolAudio;

  /// Bottom toolbar button: text overlays (not yet built)
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get timelineToolText;

  /// Bottom toolbar button: visual effects (not yet built)
  ///
  /// In en, this message translates to:
  /// **'Effects'**
  String get timelineToolEffects;

  /// Bottom toolbar button: image/video overlays (not yet built)
  ///
  /// In en, this message translates to:
  /// **'Overlay'**
  String get timelineToolOverlay;

  /// Bottom toolbar button: toggles the caption list under the track area
  ///
  /// In en, this message translates to:
  /// **'Captions'**
  String get timelineToolCaptions;

  /// Bottom toolbar button: colour filters (not yet built)
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get timelineToolFilter;

  /// Acknowledgement shown when a Timeline mode tool without a real implementation yet is tapped
  ///
  /// In en, this message translates to:
  /// **'{feature} is coming soon.'**
  String timelineComingSoon(String feature);

  /// Shown on an empty project's timeline and in Script mode when the project has no clips
  ///
  /// In en, this message translates to:
  /// **'No media yet. Tap + to add a clip.'**
  String get timelineNoClips;

  /// Accessibility label of the + button that adds media to a project
  ///
  /// In en, this message translates to:
  /// **'Add a clip'**
  String get clipAdd;

  /// Menu entry that removes a clip from the project
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get clipRemove;

  /// Heading of the dialog confirming a clip's removal
  ///
  /// In en, this message translates to:
  /// **'Remove this clip?'**
  String get clipRemoveTitle;

  /// Body of the clip-removal confirmation, stating that the media is permanently deleted
  ///
  /// In en, this message translates to:
  /// **'This deletes the clip\'s media from your device, along with anything transcribed from it. It cannot be undone.'**
  String get clipRemoveMessage;

  /// Menu entry that moves a clip one place towards the start of the timeline
  ///
  /// In en, this message translates to:
  /// **'Move earlier'**
  String get clipMoveEarlier;

  /// Menu entry that moves a clip one place towards the end of the timeline
  ///
  /// In en, this message translates to:
  /// **'Move later'**
  String get clipMoveLater;

  /// Button that starts transcribing the selected clip
  ///
  /// In en, this message translates to:
  /// **'Transcribe'**
  String get clipTranscribe;

  /// Shown beside the Transcribe button when the selected clip has no transcript
  ///
  /// In en, this message translates to:
  /// **'Not transcribed yet.'**
  String get clipNotTranscribed;

  /// Shown in Script mode when the selected clip has no transcript, pointing at where the action lives
  ///
  /// In en, this message translates to:
  /// **'This clip hasn\'t been transcribed yet. Switch to Timeline and tap Transcribe to start.'**
  String get clipNotTranscribedScript;

  /// Shown beside the selected clip once it has a transcript
  ///
  /// In en, this message translates to:
  /// **'Transcribed.'**
  String get clipTranscribed;

  /// Shown when transcribing a clip failed; the clip itself is unaffected and the action can be retried
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t transcribe this clip.'**
  String get clipTranscribeFailed;

  /// Label on the library panel that creates an empty project and opens it on the timeline
  ///
  /// In en, this message translates to:
  /// **'Create project'**
  String get createProjectHeadline;

  /// Supporting line under the create-project panel
  ///
  /// In en, this message translates to:
  /// **'Name it, then add clips on the timeline'**
  String get createProjectSubhead;

  /// Heading of the dialog asking for a new project's name
  ///
  /// In en, this message translates to:
  /// **'Name this project'**
  String get createProjectTitle;

  /// Button that confirms creating the named project
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get createProjectAction;

  /// The name a project gets when the user confirms without typing one
  ///
  /// In en, this message translates to:
  /// **'Untitled project'**
  String get createProjectDefaultName;

  /// Button that draws a new transcribe layer on the timeline
  ///
  /// In en, this message translates to:
  /// **'Add layer'**
  String get layerAdd;

  /// Title of the dialog confirming a layer is transcribed a second time
  ///
  /// In en, this message translates to:
  /// **'Transcribe this layer again?'**
  String get layerRerunTitle;

  /// Body of the re-transcribe confirmation, naming specifically what the run discards
  ///
  /// In en, this message translates to:
  /// **'The words this layer produced will be replaced. Any corrections you typed and any speaker names you set on them are lost.'**
  String get layerRerunBody;

  /// Confirming button of the re-transcribe dialog
  ///
  /// In en, this message translates to:
  /// **'Transcribe again'**
  String get layerRerunConfirm;

  /// Button that removes the selected transcribe layer and anything it transcribed
  ///
  /// In en, this message translates to:
  /// **'Remove layer'**
  String get layerRemove;

  /// Shown beside the transcribe track when no layer is selected
  ///
  /// In en, this message translates to:
  /// **'Add a layer to mark what to transcribe.'**
  String get layerHint;

  /// Shown beside the transcribe track when a layer is selected
  ///
  /// In en, this message translates to:
  /// **'Layer selected.'**
  String get layerSelected;

  /// Shown when a new transcribe layer would not fit without overlapping an existing one
  ///
  /// In en, this message translates to:
  /// **'No room for another layer here.'**
  String get layerNoRoom;

  /// Tooltip on the gutter control that reveals a hidden timeline track
  ///
  /// In en, this message translates to:
  /// **'Show track'**
  String get trackShow;

  /// Tooltip on the gutter control that hides a timeline track
  ///
  /// In en, this message translates to:
  /// **'Hide track'**
  String get trackHide;

  /// Tooltip on the gutter handle that swaps the vertical order of the timeline tracks
  ///
  /// In en, this message translates to:
  /// **'Reorder tracks'**
  String get trackReorder;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
