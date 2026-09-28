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
  /// **'Model'**
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

  /// Language option pinning transcription to English
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// Header of the settings section toggling voice activity detection
  ///
  /// In en, this message translates to:
  /// **'Skip silence'**
  String get silenceSkippingTitle;

  /// Subtitle explaining what the silence-skipping toggle does
  ///
  /// In en, this message translates to:
  /// **'Faster when there are pauses. Can be slower on non-stop speech.'**
  String get silenceSkippingHint;

  /// Header of the settings section toggling speaker diarization
  ///
  /// In en, this message translates to:
  /// **'Identify speakers'**
  String get diarizationTitle;

  /// Subtitle explaining what the speaker-identification toggle does
  ///
  /// In en, this message translates to:
  /// **'Slower. Skipped on very long recordings.'**
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

  /// Hint inside the library search field, which matches project names and transcribed words
  ///
  /// In en, this message translates to:
  /// **'Search projects and words'**
  String get librarySearchHint;

  /// Tooltip on the button that empties the library search field
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get librarySearchClear;

  /// Red button that removes the selected clip or caption layer from the timeline
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get selectionRemove;

  /// Strip label when a clip's audio is selected on its own
  ///
  /// In en, this message translates to:
  /// **'Sound selected.'**
  String get audioSelected;

  /// Button that puts a removed clip sound back on the timeline
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get audioRestore;

  /// Button on selected captions that translates them into another language
  ///
  /// In en, this message translates to:
  /// **'Translate'**
  String get translateAction;

  /// Title of the language list used to pick what to translate captions into
  ///
  /// In en, this message translates to:
  /// **'Translate to'**
  String get translateTitle;

  /// Under a language not yet on the device: its offline pack's size
  ///
  /// In en, this message translates to:
  /// **'About 30 MB, downloaded once'**
  String get translatePackSize;

  /// Under a language whose offline pack is being downloaded
  ///
  /// In en, this message translates to:
  /// **'Downloading…'**
  String get translateDownloading;

  /// Tooltip on the button that removes a downloaded language pack
  ///
  /// In en, this message translates to:
  /// **'Delete download'**
  String get translateDeletePack;

  /// Row in the language list that deletes the existing translation
  ///
  /// In en, this message translates to:
  /// **'Remove translation'**
  String get translateRemove;

  /// Row in the Transcribe sheet's language list meaning: do not translate
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get translateOff;

  /// Shown while captions are being translated on the device
  ///
  /// In en, this message translates to:
  /// **'Translating…'**
  String get translateWorking;

  /// Confirmation after translating captions
  ///
  /// In en, this message translates to:
  /// **'Translated to {language}'**
  String translateDone(String language);

  /// Error when the transcript's own language has no translation pack
  ///
  /// In en, this message translates to:
  /// **'This transcript\'s language can\'t be translated yet.'**
  String get translateUnsupported;

  /// Error when a language pack download fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t download the language. Check your connection and try again.'**
  String get translateDownloadFailed;

  /// Error when on-device translation itself fails
  ///
  /// In en, this message translates to:
  /// **'Translation failed. Try again.'**
  String get translateFailed;

  /// Row in the Transcribe sheet choosing a language to also translate the transcription into
  ///
  /// In en, this message translates to:
  /// **'Translate to'**
  String get translateToOption;

  /// Label of the timeline track holding the translated lines
  ///
  /// In en, this message translates to:
  /// **'Translation'**
  String get translationTrack;

  /// Script mode option that shows each sentence's translation under it
  ///
  /// In en, this message translates to:
  /// **'Show translation'**
  String get showTranslation;

  /// Script edit mode: placeholder under a caption row with no translation; tapping it types one
  ///
  /// In en, this message translates to:
  /// **'Add translation'**
  String get translationAdd;

  /// Subtitle export option adding each line's translation under it
  ///
  /// In en, this message translates to:
  /// **'Include translation'**
  String get exportIncludeTranslation;

  /// Shown in the library when a search finds nothing
  ///
  /// In en, this message translates to:
  /// **'No project names or words match.'**
  String get librarySearchEmpty;

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

  /// Settings label for the colour every call-to-action button takes
  ///
  /// In en, this message translates to:
  /// **'Action colour'**
  String get settingsAccentColor;

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

  /// Explanation under the Text track kind
  ///
  /// In en, this message translates to:
  /// **'Words on the picture, at the playhead.'**
  String get trackKindTextDetail;

  /// The zoom slider's current value
  ///
  /// In en, this message translates to:
  /// **'{percent}%'**
  String zoomPercent(int percent);

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

  /// Add-track sheet: what an image track item is
  ///
  /// In en, this message translates to:
  /// **'A picture over the video, at the playhead.'**
  String get trackKindImageDetail;

  /// Selection strip: one translation line is selected
  ///
  /// In en, this message translates to:
  /// **'Translation line selected.'**
  String get translationSelected;

  /// Selection strip: one image is selected
  ///
  /// In en, this message translates to:
  /// **'Image selected.'**
  String get imageSelected;

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

  /// Bottom toolbar button that scales the selected clip's picture
  ///
  /// In en, this message translates to:
  /// **'Zoom'**
  String get timelineToolZoom;

  /// Bottom toolbar button that turns the selected clip's picture a quarter turn
  ///
  /// In en, this message translates to:
  /// **'Rotate'**
  String get timelineToolRotate;

  /// Shown under the tracks while several timeline items are selected
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String selectionCount(int count);

  /// Deletes every selected timeline item
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get selectionDelete;

  /// Ends multi-select and clears the selection
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get selectionDone;

  /// Shown under the tracks when nothing is selected, explaining tap versus long press
  ///
  /// In en, this message translates to:
  /// **'Tap to edit · hold to select several'**
  String get selectionHint;

  /// Shown under the tracks when one text layer is selected
  ///
  /// In en, this message translates to:
  /// **'Text selected.'**
  String get textSelected;

  /// Opens the words of the selected text layer for editing
  ///
  /// In en, this message translates to:
  /// **'Edit text'**
  String get textEdit;

  /// Shown under the tracks when one transcribed sentence is selected
  ///
  /// In en, this message translates to:
  /// **'Sentence selected.'**
  String get sentenceSelected;

  /// The word a new text layer starts with, selected so typing replaces it
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get textPlaceholder;

  /// Shown under the tracks when one clip is selected
  ///
  /// In en, this message translates to:
  /// **'Clip selected.'**
  String get clipSelected;

  /// Bottom toolbar button that opens fonts, colours and caption styles
  ///
  /// In en, this message translates to:
  /// **'Style'**
  String get timelineToolStyle;

  /// Style panel item: the typeface
  ///
  /// In en, this message translates to:
  /// **'Font'**
  String get styleFont;

  /// Style panel item: the colour of the words
  ///
  /// In en, this message translates to:
  /// **'Colour'**
  String get styleColor;

  /// Style panel item: how a caption's words appear as they are spoken
  ///
  /// In en, this message translates to:
  /// **'Animation'**
  String get styleCaption;

  /// Style panel item: the colour the spoken word takes
  ///
  /// In en, this message translates to:
  /// **'Highlight'**
  String get styleHighlight;

  /// Style panel scope: every caption in the project
  ///
  /// In en, this message translates to:
  /// **'All captions'**
  String get styleScopeAll;

  /// Style panel, when there is nothing it can style
  ///
  /// In en, this message translates to:
  /// **'Select a text or caption to style it.'**
  String get styleNothing;

  /// Colour choice meaning each caption takes its speaker's colour
  ///
  /// In en, this message translates to:
  /// **'Speaker'**
  String get styleColorSpeaker;

  /// Colour choice meaning the default colour
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get styleColorDefault;

  /// Caption animation: the whole line at once
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get styleModeStandard;

  /// Caption animation: words fill with colour as they are spoken
  ///
  /// In en, this message translates to:
  /// **'Karaoke'**
  String get styleModeKaraoke;

  /// Caption animation: one word at a time
  ///
  /// In en, this message translates to:
  /// **'Word'**
  String get styleModeWordByWord;

  /// Caption animation: the spoken word is picked out
  ///
  /// In en, this message translates to:
  /// **'Highlight'**
  String get styleModeHighlight;

  /// Highlight drawn as a box behind the word
  ///
  /// In en, this message translates to:
  /// **'Box'**
  String get styleHighlightBox;

  /// Highlight drawn as the word's own colour
  ///
  /// In en, this message translates to:
  /// **'Letters'**
  String get styleHighlightLetters;

  /// Style panel scope: only the selected items
  ///
  /// In en, this message translates to:
  /// **'Selected ({count})'**
  String styleScopeSelected(int count);

  /// Style panel item: the drop shadow under the words
  ///
  /// In en, this message translates to:
  /// **'Shadow'**
  String get styleShadow;

  /// Shadow strength readout at zero
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get styleShadowNone;

  /// Shown under the shadow dial when the words have a background colour
  ///
  /// In en, this message translates to:
  /// **'Words on a background have no shadow.'**
  String get styleShadowOnBackground;

  /// Colour target: the words themselves
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get styleColorText;

  /// Colour target: a colour behind the words
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get styleColorBackground;

  /// Background colour option: no background
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get styleColorNone;

  /// Accessibility label for the colour spectrum slider
  ///
  /// In en, this message translates to:
  /// **'Hue'**
  String get styleHue;

  /// Accessibility label for the dark-to-light slider
  ///
  /// In en, this message translates to:
  /// **'Shade'**
  String get styleShade;

  /// Timeline toolbar action that cuts the selected clip in two at the playhead
  ///
  /// In en, this message translates to:
  /// **'Split'**
  String get timelineToolSplit;

  /// Shown when a split would leave a piece too short to play
  ///
  /// In en, this message translates to:
  /// **'Too close to the edge of the clip to split.'**
  String get splitTooClose;

  /// Shown when Split is used with an empty selection
  ///
  /// In en, this message translates to:
  /// **'Select something on the timeline to split.'**
  String get splitNothingSelected;

  /// Shown when Split runs but the playhead falls outside every selected item
  ///
  /// In en, this message translates to:
  /// **'The playhead is not over anything selected.'**
  String get splitNotUnderPlayhead;

  /// Confirmation that the clip was cut in two
  ///
  /// In en, this message translates to:
  /// **'Clip split.'**
  String get splitDone;

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

  /// Label above the output size choices
  ///
  /// In en, this message translates to:
  /// **'Resolution'**
  String get exportOptionsQuality;

  /// Label above the output shape choices
  ///
  /// In en, this message translates to:
  /// **'Aspect ratio'**
  String get exportOptionsAspect;

  /// Output size preset, 720 pixels on the short edge
  ///
  /// In en, this message translates to:
  /// **'720p'**
  String get exportQuality720;

  /// Output size preset, 1080 pixels on the short edge
  ///
  /// In en, this message translates to:
  /// **'1080p'**
  String get exportQuality1080;

  /// Output size preset, 1440 pixels on the short edge
  ///
  /// In en, this message translates to:
  /// **'2K'**
  String get exportQuality1440;

  /// Output size preset, 2160 pixels on the short edge
  ///
  /// In en, this message translates to:
  /// **'4K'**
  String get exportQuality2160;

  /// Output size preset meaning keep the clip's own size
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get exportQualitySource;

  /// Output shape preset meaning keep the clip's own shape
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get exportAspectSource;

  /// Tall output shape, for stories and reels
  ///
  /// In en, this message translates to:
  /// **'9:16'**
  String get exportAspectPortrait;

  /// Square output shape
  ///
  /// In en, this message translates to:
  /// **'1:1'**
  String get exportAspectSquare;

  /// Slightly tall output shape, for feed posts
  ///
  /// In en, this message translates to:
  /// **'4:5'**
  String get exportAspectFeed;

  /// Wide output shape
  ///
  /// In en, this message translates to:
  /// **'16:9'**
  String get exportAspectWide;

  /// The pixel size the render will produce, shown under the framing preview
  ///
  /// In en, this message translates to:
  /// **'{width} x {height}'**
  String exportFrameSize(int width, int height);

  /// Toggle that leaves the app's mark off the exported video
  ///
  /// In en, this message translates to:
  /// **'Remove watermark'**
  String get exportRemoveWatermark;

  /// What removing the watermark costs
  ///
  /// In en, this message translates to:
  /// **'Watch a short ad first'**
  String get exportRemoveWatermarkDetail;

  /// Button that begins the render with the chosen options
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get exportStart;

  /// Header of the window shown while the video is being rendered
  ///
  /// In en, this message translates to:
  /// **'Rendering video'**
  String get exportProgressTitle;

  /// Shown before the renderer reports a percentage
  ///
  /// In en, this message translates to:
  /// **'Preparing...'**
  String get exportProgressPreparing;

  /// How far through the render is
  ///
  /// In en, this message translates to:
  /// **'{percent}%'**
  String exportProgressPercent(int percent);

  /// Advice shown under the render progress bar
  ///
  /// In en, this message translates to:
  /// **'Keep the app open while this finishes.'**
  String get exportProgressNote;

  /// Button that stops a render already under way
  ///
  /// In en, this message translates to:
  /// **'Cancel export'**
  String get exportCancel;

  /// Export sheet tab for rendering the timeline to a video file
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get exportTabVideo;

  /// Export sheet tab for a SubRip subtitle file
  ///
  /// In en, this message translates to:
  /// **'SRT'**
  String get exportTabSrt;

  /// Export sheet tab for a WebVTT subtitle file
  ///
  /// In en, this message translates to:
  /// **'VTT'**
  String get exportTabVtt;

  /// Export sheet tab listing professional formats that come with Pro
  ///
  /// In en, this message translates to:
  /// **'Pro formats'**
  String get exportTabPro;

  /// Export button when the user has chosen to remove the watermark by watching an ad
  ///
  /// In en, this message translates to:
  /// **'Watch ad, then export'**
  String get exportWatchAdThenExport;

  /// Shown when no ad could be loaded, usually because the device is offline
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the ad — the watermark stays on.'**
  String get exportAdOffline;

  /// Shown when the ad was closed before it finished
  ///
  /// In en, this message translates to:
  /// **'Watch the ad to the end to remove the watermark.'**
  String get exportAdIncomplete;

  /// Shown in place of the watermark toggle when Pro is owned
  ///
  /// In en, this message translates to:
  /// **'No watermark — included with Pro'**
  String get exportProIncluded;

  /// Label above the subtitle line-length choices
  ///
  /// In en, this message translates to:
  /// **'Line length'**
  String get exportLineLength;

  /// Subtitle line length suited to landscape video
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get exportLineStandard;

  /// Subtitle line length suited to vertical video
  ///
  /// In en, this message translates to:
  /// **'Short'**
  String get exportLineShort;

  /// Explains when to choose short subtitle lines
  ///
  /// In en, this message translates to:
  /// **'Short lines suit vertical video.'**
  String get exportLineHint;

  /// Explains that subtitle files follow the edited project
  ///
  /// In en, this message translates to:
  /// **'Timed to the whole timeline, so it lines up with the exported video.'**
  String get exportSubtitlesTimed;

  /// Shown on the subtitle tabs when nothing in the project has been transcribed
  ///
  /// In en, this message translates to:
  /// **'Transcribe something first — there are no captions to export yet.'**
  String get exportSubtitlesNeedTranscript;

  /// Introduces the Pro formats tab
  ///
  /// In en, this message translates to:
  /// **'Formats for professional editing tools.'**
  String get exportProFormatsIntro;

  /// Advanced SubStation Alpha subtitle format
  ///
  /// In en, this message translates to:
  /// **'ASS / SSA'**
  String get exportProFormatAss;

  /// What the ASS format adds
  ///
  /// In en, this message translates to:
  /// **'Styled subtitles with speaker colours'**
  String get exportProFormatAssDetail;

  /// Final Cut Pro interchange format
  ///
  /// In en, this message translates to:
  /// **'Final Cut Pro (FCPXML)'**
  String get exportProFormatFcpxml;

  /// What the FCPXML format adds
  ///
  /// In en, this message translates to:
  /// **'Captions as titles on your timeline'**
  String get exportProFormatFcpxmlDetail;

  /// Adobe Premiere interchange format
  ///
  /// In en, this message translates to:
  /// **'Premiere Pro (XML)'**
  String get exportProFormatPremiere;

  /// What the Premiere format adds
  ///
  /// In en, this message translates to:
  /// **'Captions as a caption track'**
  String get exportProFormatPremiereDetail;

  /// Marks a format that is not built yet and will be part of Pro
  ///
  /// In en, this message translates to:
  /// **'Coming with Pro'**
  String get exportProComing;

  /// Name of the one-time purchase
  ///
  /// In en, this message translates to:
  /// **'Argand Pro'**
  String get exportProName;

  /// What the one-time Pro purchase gives, shown before every export
  ///
  /// In en, this message translates to:
  /// **'One payment. No watermark, no ads.'**
  String get exportProPitch;

  /// Button that will open the one-time Pro purchase
  ///
  /// In en, this message translates to:
  /// **'Get Pro'**
  String get exportGetPro;

  /// Header of the stand-in shown where a rewarded ad will play
  ///
  /// In en, this message translates to:
  /// **'Test ad'**
  String get adPlaceholderLabel;

  /// Explains that this is not a real advert
  ///
  /// In en, this message translates to:
  /// **'Shown when the ad network has nothing to play. Watch to the end to export this video without the watermark, or get Pro to skip ads for good.'**
  String get adPlaceholderBody;

  /// Button shown once the placeholder ad has finished
  ///
  /// In en, this message translates to:
  /// **'Continue to export'**
  String get adPlaceholderContinue;

  /// Tooltip on the control that closes the ad early
  ///
  /// In en, this message translates to:
  /// **'Close ad'**
  String get adPlaceholderClose;

  /// Seconds left before the placeholder ad can be claimed
  ///
  /// In en, this message translates to:
  /// **'{seconds}'**
  String adPlaceholderSeconds(int seconds);

  /// Tooltip on the gear that opens the video settings panel
  ///
  /// In en, this message translates to:
  /// **'Video settings'**
  String get videoSettingsOpen;

  /// Shows the watermark in the preview
  ///
  /// In en, this message translates to:
  /// **'Visible'**
  String get videoSettingsVisible;

  /// Hides the watermark in the preview
  ///
  /// In en, this message translates to:
  /// **'Hidden'**
  String get videoSettingsHidden;

  /// Label beside the Visible/Hidden choice for showing the watermark in the editor's preview
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get videoSettingsWatermarkPreview;

  /// Watermark corner
  ///
  /// In en, this message translates to:
  /// **'Upper left'**
  String get watermarkTopLeft;

  /// Watermark corner
  ///
  /// In en, this message translates to:
  /// **'Upper right'**
  String get watermarkTopRight;

  /// Watermark corner
  ///
  /// In en, this message translates to:
  /// **'Lower left'**
  String get watermarkBottomLeft;

  /// Watermark corner
  ///
  /// In en, this message translates to:
  /// **'Lower right'**
  String get watermarkBottomRight;

  /// Tooltip on the gear while the settings panel is open
  ///
  /// In en, this message translates to:
  /// **'Close video settings'**
  String get videoSettingsClose;

  /// Settings panel item for the watermark's visibility and position
  ///
  /// In en, this message translates to:
  /// **'Watermark'**
  String get videoSettingsWatermarkItem;

  /// Settings sheet row opening the transcription model manager
  ///
  /// In en, this message translates to:
  /// **'Transcription models'**
  String get settingsModels;

  /// Second line of the Transcription models settings row
  ///
  /// In en, this message translates to:
  /// **'Add, remove and choose on-device models'**
  String get settingsModelsDetail;

  /// Settings sheet row opening the translation language pack manager
  ///
  /// In en, this message translates to:
  /// **'Translation languages'**
  String get settingsLanguages;

  /// Second line of the Translation languages settings row
  ///
  /// In en, this message translates to:
  /// **'Download or remove language packs'**
  String get settingsLanguagesDetail;

  /// Explanation at the top of the language pack manager
  ///
  /// In en, this message translates to:
  /// **'Each language is a pack of about 30 MB, downloaded once. Text is always translated on this device.'**
  String get languagesNote;

  /// Button that downloads and installs a model or language pack
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get packAdd;

  /// Button that deletes a downloaded model or language pack
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get packRemove;

  /// Status of a model or language that ships with the app and cannot be removed
  ///
  /// In en, this message translates to:
  /// **'Built in'**
  String get packBuiltIn;

  /// Status of a downloaded language pack
  ///
  /// In en, this message translates to:
  /// **'Downloaded'**
  String get packInstalled;

  /// Status of a model or language pack that is not on the device
  ///
  /// In en, this message translates to:
  /// **'Not downloaded'**
  String get packNotInstalled;

  /// Status while a download is queued
  ///
  /// In en, this message translates to:
  /// **'Waiting…'**
  String get packWaiting;

  /// Status while a downloaded pack is moved into place
  ///
  /// In en, this message translates to:
  /// **'Installing…'**
  String get packInstalling;

  /// Status after a download failed
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t download. Try again.'**
  String get packFailed;

  /// Status of an installed model file whose header is not a whisper.cpp model
  ///
  /// In en, this message translates to:
  /// **'Not a Whisper model this app can run'**
  String get modelNotLoadable;

  /// Title of the dialog confirming a model or language pack removal
  ///
  /// In en, this message translates to:
  /// **'Remove {name}?'**
  String packRemoveTitle(String name);

  /// Body of the dialog confirming a model or language pack removal
  ///
  /// In en, this message translates to:
  /// **'It frees the space it takes, and can be added again at any time.'**
  String get packRemoveBody;

  /// Status while a pack downloads
  ///
  /// In en, this message translates to:
  /// **'Downloading {percent}%'**
  String packDownloading(int percent);

  /// A pack's size on the device
  ///
  /// In en, this message translates to:
  /// **'{size} MB'**
  String packMegabytes(String size);

  /// Status of an installed model that can run, with what its file says about it, e.g. 'small · q5_1 · 12 layers'
  ///
  /// In en, this message translates to:
  /// **'Ready · {details}'**
  String modelReady(String details);

  /// A model's encoder depth, in its status line
  ///
  /// In en, this message translates to:
  /// **'{count} layers'**
  String modelLayers(int count);

  /// Status while a pack downloads and its size is not known
  ///
  /// In en, this message translates to:
  /// **'Downloading…'**
  String get packDownloadingUnknown;

  /// Buy button while the price loads from the store
  ///
  /// In en, this message translates to:
  /// **'Getting the price…'**
  String get proBuyLoading;

  /// Shown when the Pro offer could not be loaded
  ///
  /// In en, this message translates to:
  /// **'The store can\'t be reached right now. Check your connection.'**
  String get proUnavailable;

  /// Buy button when the offer could not be loaded
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get proRetry;

  /// Shown when Restore found nothing
  ///
  /// In en, this message translates to:
  /// **'No Pro purchase was found to restore.'**
  String get proRestoreNone;

  /// Shown when a purchase or restore failed for lack of connection
  ///
  /// In en, this message translates to:
  /// **'No connection to the store. Try again when you\'re online.'**
  String get proOffline;

  /// Shown when a purchase failed
  ///
  /// In en, this message translates to:
  /// **'The purchase didn\'t go through. Please try again.'**
  String get proFailed;

  /// Note at the top of the model manager
  ///
  /// In en, this message translates to:
  /// **'Larger models are more accurate but consume more resources.'**
  String get modelsNoteShort;

  /// Confirm button of the download prompt
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get packDownload;

  /// Download prompt body for a transcription model
  ///
  /// In en, this message translates to:
  /// **'It\'s saved on this device and can be removed at any time.'**
  String get packDownloadModelBody;

  /// Download prompt body for a translation language
  ///
  /// In en, this message translates to:
  /// **'About 30 MB, downloaded once.'**
  String get packDownloadLanguageBody;

  /// Title of the prompt before downloading a model or language pack
  ///
  /// In en, this message translates to:
  /// **'Download {name}?'**
  String packDownloadTitle(String name);

  /// Shown on the Pro page when the store has no Pro product set up
  ///
  /// In en, this message translates to:
  /// **'Pro isn\'t on sale yet. Please check back soon.'**
  String get proNotOnSale;

  /// Badge under the logo on the Pro page
  ///
  /// In en, this message translates to:
  /// **'One-time · No subscription'**
  String get proHeroBadge;

  /// Pro page headline, two lines
  ///
  /// In en, this message translates to:
  /// **'Pay once.\nKeep Argand yours.'**
  String get proHeadline;

  /// Pro page line under the headline
  ///
  /// In en, this message translates to:
  /// **'Transcription and editing stay free. This removes the extras and keeps the app going.'**
  String get proLede;

  /// Pro benefit
  ///
  /// In en, this message translates to:
  /// **'Support the developer'**
  String get proSupportTitle;

  /// Pro benefit detail
  ///
  /// In en, this message translates to:
  /// **'Funds fixes, updates and new features'**
  String get proSupportDetail;

  /// Pro benefit
  ///
  /// In en, this message translates to:
  /// **'No ads'**
  String get proNoAdsTitle;

  /// Pro benefit detail
  ///
  /// In en, this message translates to:
  /// **'Nothing between you and your edit'**
  String get proNoAdsDetail;

  /// Pro benefit
  ///
  /// In en, this message translates to:
  /// **'No watermark'**
  String get proNoWatermarkTitle;

  /// Pro benefit detail
  ///
  /// In en, this message translates to:
  /// **'Clean exports, every time'**
  String get proNoWatermarkDetail;

  /// Pro benefit
  ///
  /// In en, this message translates to:
  /// **'Any new future Pro features'**
  String get proFutureTitle;

  /// Pro benefit detail
  ///
  /// In en, this message translates to:
  /// **'Everything Pro gains later is yours too'**
  String get proFutureDetail;

  /// After the price on the Pro page
  ///
  /// In en, this message translates to:
  /// **'once'**
  String get proOnce;

  /// Beside the price on the Pro page, two lines
  ///
  /// In en, this message translates to:
  /// **'Yours for good.\nNo renewals.'**
  String get proForGood;

  /// Small print under the unlock button
  ///
  /// In en, this message translates to:
  /// **'One-time purchase, charged to your Google Play account.'**
  String get proFinePrint;

  /// Top-bar button that restores an earlier Pro purchase
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get proRestoreShort;

  /// Badge on the thank-you after buying Pro
  ///
  /// In en, this message translates to:
  /// **'Supporter'**
  String get proThanksBadge;

  /// Thank-you headline after buying Pro
  ///
  /// In en, this message translates to:
  /// **'Thank you.'**
  String get proThanksTitle;

  /// Thank-you line after buying Pro
  ///
  /// In en, this message translates to:
  /// **'You\'re helping keep Argand independent. The extras are gone for good.'**
  String get proThanksBody;

  /// Thank-you check list item
  ///
  /// In en, this message translates to:
  /// **'Ads removed'**
  String get proThanksAds;

  /// Thank-you check list item
  ///
  /// In en, this message translates to:
  /// **'Watermark removed from exports'**
  String get proThanksWatermark;

  /// Thank-you check list item
  ///
  /// In en, this message translates to:
  /// **'Every future Pro feature, included'**
  String get proThanksFuture;

  /// Thank-you check list item
  ///
  /// In en, this message translates to:
  /// **'Restore anytime on a new device'**
  String get proThanksRestore;

  /// Thank-you button back to the library
  ///
  /// In en, this message translates to:
  /// **'Back to projects'**
  String get proThanksBack;

  /// Pro page buy button with the store's price
  ///
  /// In en, this message translates to:
  /// **'Unlock for {price}'**
  String proUnlock(String price);

  /// Hidden test-only dialog title (long-press the logo in a Test Store build)
  ///
  /// In en, this message translates to:
  /// **'Reset Pro for testing?'**
  String get proResetTitle;

  /// Hidden test-only dialog body
  ///
  /// In en, this message translates to:
  /// **'Starts over as a new test customer, so Pro is off until it\'s bought again. Test Store purchases are simulated and cost nothing.'**
  String get proResetBody;

  /// Hidden test-only dialog confirm
  ///
  /// In en, this message translates to:
  /// **'Reset Pro'**
  String get proResetAction;

  /// Shown after Pro was reset for testing
  ///
  /// In en, this message translates to:
  /// **'Pro is off. Ready for another take.'**
  String get proResetDone;

  /// Shown when resetting Pro for testing failed
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reset Pro. Check the connection and try again.'**
  String get proResetFailed;

  /// Row under the model choice in the transcribe dialog; opens the model management page
  ///
  /// In en, this message translates to:
  /// **'Manage models'**
  String get transcriptionMoreModels;

  /// Style panel scope: apply the change to everything said by the speakers of what is selected
  ///
  /// In en, this message translates to:
  /// **'Per speaker'**
  String get styleScopeSpeaker;

  /// Style panel scope when only translation lines are selected: apply to every translation line
  ///
  /// In en, this message translates to:
  /// **'All translations'**
  String get styleScopeAllTranslations;
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
