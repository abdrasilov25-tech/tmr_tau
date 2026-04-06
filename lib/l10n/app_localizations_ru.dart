// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'ТМР Тау';

  @override
  String get tabPublications => 'Публикации';

  @override
  String get tabSearch => 'Поиск';

  @override
  String get tabNearby => 'Рядом';

  @override
  String get tabChats => 'Чаты';

  @override
  String get tabNews => 'Новости';

  @override
  String get tabProfile => 'Профиль';

  @override
  String get settingsTitle => 'Настройки';

  @override
  String get loginLegalPrefix => 'Продолжая, вы принимаете ';

  @override
  String get loginLegalTerms => 'условия';

  @override
  String get loginLegalMiddle => ' и ';

  @override
  String get loginLegalPrivacy => 'политику конфиденциальности';

  @override
  String get loginLegalSuffix => '.';

  @override
  String get couldNotOpenLink => 'Не удалось открыть ссылку';

  @override
  String get moderationReportHint =>
      'Жалобы рассматриваются модерацией. Ложные сообщения могут ограничить доступ к функциям.';
}
