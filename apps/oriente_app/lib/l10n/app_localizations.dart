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

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
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

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'VIVEI'**
  String get appTitle;

  /// No description provided for @tapAndSpeak.
  ///
  /// In en, this message translates to:
  /// **'Tap and speak'**
  String get tapAndSpeak;

  /// No description provided for @tapAndSpeakHint.
  ///
  /// In en, this message translates to:
  /// **'Double tap to open listening mode and say a request'**
  String get tapAndSpeakHint;

  /// No description provided for @listening.
  ///
  /// In en, this message translates to:
  /// **'Listening…'**
  String get listening;

  /// No description provided for @listeningHint.
  ///
  /// In en, this message translates to:
  /// **'Speak your request. Say stop to cancel.'**
  String get listeningHint;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @cancelHint.
  ///
  /// In en, this message translates to:
  /// **'Stop the current action and return home'**
  String get cancelHint;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @settingsHint.
  ///
  /// In en, this message translates to:
  /// **'Open settings for speech rate, privacy, and models'**
  String get settingsHint;

  /// No description provided for @statusIdle.
  ///
  /// In en, this message translates to:
  /// **'Ready. Tap the button and speak.'**
  String get statusIdle;

  /// No description provided for @objectSearchTitle.
  ///
  /// In en, this message translates to:
  /// **'Object Search'**
  String get objectSearchTitle;

  /// No description provided for @speechRate.
  ///
  /// In en, this message translates to:
  /// **'Speech rate'**
  String get speechRate;

  /// No description provided for @speechVolume.
  ///
  /// In en, this message translates to:
  /// **'Speech volume'**
  String get speechVolume;

  /// No description provided for @onlineVisionConsent.
  ///
  /// In en, this message translates to:
  /// **'Allow online vision upgrades'**
  String get onlineVisionConsent;

  /// No description provided for @onlineChatConsent.
  ///
  /// In en, this message translates to:
  /// **'Allow online conversational answers'**
  String get onlineChatConsent;

  /// No description provided for @privacySection.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get privacySection;

  /// No description provided for @speechSection.
  ///
  /// In en, this message translates to:
  /// **'Speech'**
  String get speechSection;

  /// No description provided for @modelsSection.
  ///
  /// In en, this message translates to:
  /// **'Offline models'**
  String get modelsSection;

  /// No description provided for @voskModelStatus.
  ///
  /// In en, this message translates to:
  /// **'Vosk offline speech model'**
  String get voskModelStatus;

  /// No description provided for @voskMissing.
  ///
  /// In en, this message translates to:
  /// **'Not installed — using system speech when available (may need network).'**
  String get voskMissing;

  /// No description provided for @voskReady.
  ///
  /// In en, this message translates to:
  /// **'Installed — offline speech ready.'**
  String get voskReady;

  /// No description provided for @detectorReady.
  ///
  /// In en, this message translates to:
  /// **'Object detector ready (EfficientDet-Lite0, Apache-2.0).'**
  String get detectorReady;

  /// No description provided for @stubNotice.
  ///
  /// In en, this message translates to:
  /// **'Some features are stubs in this build.'**
  String get stubNotice;
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
