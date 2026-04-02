/// Тематические разделы официального городского чата (значение `city_thread` в БД).
class CityChatThread {
  const CityChatThread({
    required this.id,
    required this.label,
    required this.description,
    required this.iconKey,
    this.avatarAsset,
  });

  final String id;
  final String label;
  final String description;

  /// Ключ для иконки Material в UI (`city_thread_icons.dart`), если нет [avatarAsset].
  final String iconKey;

  /// Локальная картинка-аватар раздела (PNG в `assets/`).
  final String? avatarAsset;
}

abstract final class CityChatThreads {
  CityChatThreads._();

  static const String realEstate = 'real_estate';
  static const String services = 'services';
  static const String jobs = 'jobs';
  static const String purchases = 'purchases';
  static const String sales = 'sales';
  static const String dating = 'dating';
  static const String discussion = 'discussion';

  /// Поток по умолчанию (раньше `general`).
  static const String defaultThreadId = discussion;

  static const List<CityChatThread> all = <CityChatThread>[
    CityChatThread(
      id: realEstate,
      label: 'Недвижимость',
      description: 'Аренда, продажа, съём жилья и коммерции в городе',
      iconKey: 'real_estate',
      avatarAsset: 'assets/city_thread_real_estate.png',
    ),
    CityChatThread(
      id: services,
      label: 'Услуги',
      description: 'Мастера, ремонт, красота, обучение и бытовая помощь',
      iconKey: 'services',
    ),
    CityChatThread(
      id: jobs,
      label: 'Работа',
      description: 'Вакансии, подработка, резюме и поиск смены',
      iconKey: 'jobs',
    ),
    CityChatThread(
      id: purchases,
      label: 'Покупки',
      description: 'Ищу товары, технику, детские вещи — кто продаёт?',
      iconKey: 'purchases',
      avatarAsset: 'assets/city_thread_purchases.png',
    ),
    CityChatThread(
      id: sales,
      label: 'Продажи',
      description: 'Объявления о продаже вещей, техники и прочего',
      iconKey: 'sales',
      avatarAsset: 'assets/city_thread_sales.png',
    ),
    CityChatThread(
      id: dating,
      label: 'Знакомства',
      description: 'Общение и знакомства — уважительно и без спама',
      iconKey: 'dating',
    ),
    CityChatThread(
      id: discussion,
      label: 'Обсуждение',
      description: 'Новости города, мнения и свободные темы для соседей',
      iconKey: 'discussion',
      avatarAsset: 'assets/city_thread_discussion.png',
    ),
  ];

  static CityChatThread metaFor(String id) {
    for (final t in all) {
      if (t.id == id) return t;
    }
    return all.firstWhere((t) => t.id == defaultThreadId);
  }

  /// Старые значения из БД и неизвестные → безопасный раздел.
  static String normalizeThreadId(String? raw) {
    final t = raw?.trim();
    if (t == null || t.isEmpty) return defaultThreadId;
    if (all.any((e) => e.id == t)) return t;
    const legacy = <String, String>{
      'general': discussion,
      'roads': discussion,
      'checks': discussion,
      'market': sales,
      'help': services,
    };
    return legacy[t] ?? defaultThreadId;
  }
}
