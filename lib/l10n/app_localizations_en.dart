// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Tmr Tau';

  @override
  String get tabPublications => 'Home';

  @override
  String get tabSearch => 'Search';

  @override
  String get tabNearby => 'Nearby';

  @override
  String get tabChats => 'Chats';

  @override
  String get tabNews => 'News';

  @override
  String get tabProfile => 'Profile';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get loginLegalPrefix => 'By continuing you accept the ';

  @override
  String get loginLegalTerms => 'terms';

  @override
  String get loginLegalMiddle => ' and ';

  @override
  String get loginLegalPrivacy => 'privacy policy';

  @override
  String get loginLegalSuffix => '.';

  @override
  String get couldNotOpenLink => 'Could not open link';

  @override
  String get moderationReportHint =>
      'Reports are reviewed by moderators. False reports may limit access to features.';
}
