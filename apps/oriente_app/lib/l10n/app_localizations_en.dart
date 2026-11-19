// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'VIVEI';

  @override
  String get tapAndSpeak => 'Tap and speak';

  @override
  String get tapAndSpeakHint =>
      'Double tap to open listening mode and say a request';

  @override
  String get listening => 'Listening…';

  @override
  String get listeningHint => 'Speak your request. Say stop to cancel.';

  @override
  String get cancel => 'Cancel';

  @override
  String get cancelHint => 'Stop the current action and return home';

  @override
  String get settings => 'Settings';

  @override
  String get settingsHint =>
      'Open settings for speech rate, privacy, and models';

  @override
  String get statusIdle => 'Ready. Tap the button and speak.';

  @override
  String get objectSearchTitle => 'Object Search';

  @override
  String get speechRate => 'Speech rate';

  @override
  String get speechVolume => 'Speech volume';

  @override
  String get onlineVisionConsent => 'Allow online vision upgrades';

  @override
  String get onlineChatConsent => 'Allow online conversational answers';

  @override
  String get privacySection => 'Privacy';

  @override
  String get speechSection => 'Speech';

  @override
  String get modelsSection => 'Offline models';

  @override
  String get voskModelStatus => 'Vosk offline speech model';

  @override
  String get voskMissing =>
      'Not installed — using system speech when available (may need network).';

  @override
  String get voskReady => 'Installed — offline speech ready.';

  @override
  String get detectorReady =>
      'Object detector ready (EfficientDet-Lite0, Apache-2.0).';

  @override
  String get stubNotice => 'Some features are stubs in this build.';
}
