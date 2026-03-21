import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/search_filters.dart';

class SavedSearchFilter {
  const SavedSearchFilter({
    required this.title,
    required this.query,
    required this.filters,
  });

  final String title;
  final String query;
  final SearchFilters filters;

  Map<String, dynamic> toJson() => {
    'title': title,
    'query': query,
    'filters': filters.toJson(),
  };

  factory SavedSearchFilter.fromJson(Map<String, dynamic> json) {
    return SavedSearchFilter(
      title: json['title'] as String? ?? 'Сохраненный фильтр',
      query: json['query'] as String? ?? '',
      filters: SearchFilters.fromJson(
        Map<String, dynamic>.from(json['filters'] as Map? ?? const {}),
      ),
    );
  }
}

class SearchPreferencesStorage {
  SearchPreferencesStorage(this._prefs);

  final SharedPreferences _prefs;

  static const _historyKey = 'tmr_tau_search_history';
  static const _savedFiltersKey = 'tmr_tau_saved_search_filters';
  static const int _maxHistory = 15;
  static const int _maxSavedFilters = 10;

  List<String> getHistory() {
    return _prefs.getStringList(_historyKey) ?? const <String>[];
  }

  Future<void> addHistory(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final list = getHistory().where((e) => e != q).toList(growable: true);
    list.insert(0, q);
    if (list.length > _maxHistory) {
      list.removeRange(_maxHistory, list.length);
    }
    await _prefs.setStringList(_historyKey, list);
  }

  Future<void> clearHistory() => _prefs.remove(_historyKey);

  List<SavedSearchFilter> getSavedFilters() {
    final raw = _prefs.getStringList(_savedFiltersKey) ?? const <String>[];
    return raw
        .map((e) {
          try {
            return SavedSearchFilter.fromJson(
              Map<String, dynamic>.from(jsonDecode(e) as Map),
            );
          } catch (_) {
            return null;
          }
        })
        .whereType<SavedSearchFilter>()
        .toList(growable: false);
  }

  Future<void> saveFilter(SavedSearchFilter filter) async {
    final list = getSavedFilters()
        .where((e) => e.title != filter.title)
        .toList(growable: true);
    list.insert(0, filter);
    if (list.length > _maxSavedFilters) {
      list.removeRange(_maxSavedFilters, list.length);
    }
    await _prefs.setStringList(
      _savedFiltersKey,
      list.map((e) => jsonEncode(e.toJson())).toList(growable: false),
    );
  }

  Future<void> removeSavedFilter(String title) async {
    final list = getSavedFilters()
        .where((e) => e.title != title)
        .map((e) => jsonEncode(e.toJson()))
        .toList(growable: false);
    await _prefs.setStringList(_savedFiltersKey, list);
  }
}
