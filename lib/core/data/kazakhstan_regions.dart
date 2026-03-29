// Справочник областей и городов РК для фильтра поиска (как в OLX).
// Данные статические, без сети — только для UI и построения OR-фильтра по полю city.

/// Одна область / город республиканского значения.
class KzRegionEntry {
  const KzRegionEntry({
    required this.id,
    required this.name,
    required this.settlements,
  });

  final String id;
  final String name;

  /// Населённые пункты: по ним строится OR `city ilike` при выборе «вся область».
  final List<String> settlements;
}

/// API доступа к справочнику.
abstract final class KazakhstanRegions {
  KazakhstanRegions._();

  static final List<KzRegionEntry> all = List<KzRegionEntry>.unmodifiable(_all);

  static KzRegionEntry? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final r in _all) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Подпись на кнопке «Местоположение».
  static String toolbarLabel({
    required String? kzRegionId,
    required String? kzLocalityName,
    required String? legacyCity,
    double? radiusKm,
    double? centerLatitude,
  }) {
    if (radiusKm != null &&
        radiusKm > 0 &&
        centerLatitude != null) {
      return 'Рядом · ${radiusKm.toStringAsFixed(0)} км';
    }
    if (kzRegionId != null && kzRegionId.isNotEmpty) {
      final r = byId(kzRegionId);
      if (r == null) return 'Регион';
      if (kzLocalityName != null && kzLocalityName.isNotEmpty) {
        return kzLocalityName;
      }
      return r.name;
    }
    final c = legacyCity?.trim();
    if (c != null && c.isNotEmpty) return c;
    return 'Вся страна';
  }

  static final List<String> _autocompleteNames =
      List<String>.unmodifiable(_buildAutocompleteNames());

  static List<String> _buildAutocompleteNames() {
    final set = <String>{};
    for (final r in _all) {
      set.add(r.name);
      set.addAll(r.settlements);
    }
    final list = set.toList();
    list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  /// Подсказки городов при вводе (справочник РК).
  static List<String> suggestCities(String query, {int limit = 10}) {
    final q = query.trim().toLowerCase();
    if (q.length < 2) return const [];
    final lim = limit < 1 ? 10 : limit;
    final starts = <String>[];
    final contains = <String>[];
    for (final n in _autocompleteNames) {
      final ln = n.toLowerCase();
      if (ln.startsWith(q)) {
        starts.add(n);
      } else if (ln.contains(q)) {
        contains.add(n);
      }
    }
    starts.sort((a, b) => a.length.compareTo(b.length));
    contains.sort((a, b) => a.length.compareTo(b.length));
    final out = <String>[...starts, ...contains];
    if (out.length <= lim) return out;
    return out.sublist(0, lim);
  }
}

const List<KzRegionEntry> _all = [
  KzRegionEntry(
    id: 'astana',
    name: 'Астана',
    settlements: ['Астана', 'Нур-Султан'],
  ),
  KzRegionEntry(
    id: 'almaty_city',
    name: 'Алматы',
    settlements: ['Алматы'],
  ),
  KzRegionEntry(
    id: 'shymkent',
    name: 'Шымкент',
    settlements: ['Шымкент', 'Чимкент'],
  ),
  KzRegionEntry(
    id: 'abai',
    name: 'Абайская область',
    settlements: [
      'Семей',
      'Курчатов',
      'Аягоз',
      'Зыряновск',
      'Риддер',
    ],
  ),
  KzRegionEntry(
    id: 'akmola',
    name: 'Акмолинская область',
    settlements: [
      'Кокшетау',
      'Степногорск',
      'Щучинск',
      'Атбасар',
      'Макинск',
      'Ерейментау',
    ],
  ),
  KzRegionEntry(
    id: 'aktobe',
    name: 'Актюбинская область',
    settlements: [
      'Актобе',
      'Хромтау',
      'Шалкар',
      'Мартук',
      'Кандыагаш',
    ],
  ),
  KzRegionEntry(
    id: 'almaty_reg',
    name: 'Алматинская область',
    settlements: [
      'Каскелен',
      'Талдыкорган',
      'Есик',
      'Текели',
      'Уштобе',
      'Жанатас',
    ],
  ),
  KzRegionEntry(
    id: 'atyrau',
    name: 'Атырауская область',
    settlements: [
      'Атырау',
      'Кульсары',
      'Индерборский',
      'Махамбет',
    ],
  ),
  KzRegionEntry(
    id: 'vko',
    name: 'Восточно-Казахстанская область',
    settlements: [
      'Усть-Каменогорск',
      'Семей',
      'Риддер',
      'Зыряновск',
      'Аягоз',
      'Курчатов',
    ],
  ),
  KzRegionEntry(
    id: 'zhambyl',
    name: 'Жамбылская область',
    settlements: [
      'Тараз',
      'Каратау',
      'Жанатас',
      'Шу',
      'Кордай',
    ],
  ),
  KzRegionEntry(
    id: 'zhetysu',
    name: 'Жетысуская область',
    settlements: [
      'Талдыкорган',
      'Текели',
      'Сарканд',
      'Уштобе',
      'Есик',
    ],
  ),
  KzRegionEntry(
    id: 'zko',
    name: 'Западно-Казахстанская область',
    settlements: [
      'Уральск',
      'Аксай',
      'Чингирлау',
      'Зеленовский',
    ],
  ),
  KzRegionEntry(
    id: 'karaganda',
    name: 'Карагандинская область',
    settlements: [
      'Караганда',
      'Темиртау',
      'Балхаш',
      'Жезказган',
      'Сарань',
      'Приозерск',
    ],
  ),
  KzRegionEntry(
    id: 'kostanay',
    name: 'Костанайская область',
    settlements: [
      'Костанай',
      'Рудный',
      'Лисаковск',
      'Аркалык',
      'Тобыл',
    ],
  ),
  KzRegionEntry(
    id: 'kyzylorda',
    name: 'Кызылординская область',
    settlements: [
      'Кызылорда',
      'Байконур',
      'Аральск',
      'Казалинск',
    ],
  ),
  KzRegionEntry(
    id: 'mangystau',
    name: 'Мангистауская область',
    settlements: [
      'Актау',
      'Жанаозен',
      'Бейнеу',
      'Форт-Шевченко',
    ],
  ),
  KzRegionEntry(
    id: 'pavlodar',
    name: 'Павлодарская область',
    settlements: [
      'Павлодар',
      'Экибастуз',
      'Аксу',
      'Щербакты',
    ],
  ),
  KzRegionEntry(
    id: 'sko',
    name: 'Северо-Казахстанская область',
    settlements: [
      'Петропавловск',
      'Мамлютка',
      'Сергеевка',
      'Тайынша',
    ],
  ),
  KzRegionEntry(
    id: 'turkestan',
    name: 'Туркестанская область',
    settlements: [
      'Туркестан',
      'Кентау',
      'Арыс',
      'Сарыагаш',
      'Шардара',
    ],
  ),
  KzRegionEntry(
    id: 'ulytau',
    name: 'Улытауская область',
    settlements: [
      'Жезказган',
      'Сатпаев',
      'Каражал',
    ],
  ),
];
