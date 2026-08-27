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

  /// Menu entry that soft-deletes a project
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

  /// Banner shown while the transcript is in edit mode, explaining both gestures
  ///
  /// In en, this message translates to:
  /// **'Tap a word to correct it, or a speaker name to reassign the turn.'**
  String get editModeHint;

  /// Header of the sheet listing speakers to reassign a turn to
  ///
  /// In en, this message translates to:
  /// **'Who is speaking?'**
  String get reassignSpeakerTitle;

  /// Header of the field for correcting a single word's text
  ///
  /// In en, this message translates to:
  /// **'Correct this word'**
  String get editWordTitle;

  /// Reassurance under the word editor that correcting text will not move the word's timestamp
  ///
  /// In en, this message translates to:
  /// **'Timing stays the same, so captions stay in sync.'**
  String get editWordTimingNote;

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
