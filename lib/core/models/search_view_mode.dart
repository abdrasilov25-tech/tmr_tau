/// Режим отображения результатов поиска (только UI, не уходит на сервер).
enum SearchViewMode {
  /// Компактные строки: миниатюра + текст.
  list,

  /// Крупные карточки с акцентом на фото (как «галерея» в объявлениях).
  gallery,

  /// Сетка 2 колонки.
  tile,
}

extension SearchViewModeX on SearchViewMode {
  String get label => switch (this) {
        SearchViewMode.list => 'Список',
        SearchViewMode.gallery => 'Галерея',
        SearchViewMode.tile => 'Плитка',
      };
}

SearchViewMode parseSearchViewMode(String? raw) {
  if (raw == null || raw.isEmpty) return SearchViewMode.list;
  for (final e in SearchViewMode.values) {
    if (e.name == raw) return e;
  }
  return SearchViewMode.list;
}
