import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/data/kazakhstan_regions.dart';

/// Результат выбора города.
/// [city] = null означает «Весь Казахстан», конкретная строка — выбранный город.
/// Функция возвращает null если пользователь закрыл шторку без выбора.
class NewsCityPickerResult {
  const NewsCityPickerResult(this.city);
  final String? city; // null = все города
}

/// Удобный выбор города для фильтра новостей.
/// Возвращает [NewsCityPickerResult] или null если закрыто без выбора.
Future<NewsCityPickerResult?> showNewsCityPicker({
  required BuildContext context,
  String? currentCity,
}) {
  return showModalBottomSheet<NewsCityPickerResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _NewsCityPickerSheet(currentCity: currentCity),
  );
}

class _NewsCityPickerSheet extends StatefulWidget {
  const _NewsCityPickerSheet({this.currentCity});
  final String? currentCity;

  @override
  State<_NewsCityPickerSheet> createState() => _NewsCityPickerSheetState();
}

typedef _R = NewsCityPickerResult;

class _NewsCityPickerSheetState extends State<_NewsCityPickerSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  /// Плоский список всех городов и населённых пунктов.
  static final List<_CityItem> _allCities = _buildCityList();

  static List<_CityItem> _buildCityList() {
    final result = <_CityItem>[];
    for (final region in KazakhstanRegions.all) {
      // Сам регион как отдельный пункт
      result.add(_CityItem(name: region.name, isRegion: true));
      // Города региона
      for (final settlement in region.settlements) {
        if (settlement != region.name) {
          result.add(_CityItem(name: settlement, isRegion: false));
        }
      }
    }
    return result;
  }

  List<_CityItem> get _filtered {
    if (_query.isEmpty) return _allCities;
    final q = _query.toLowerCase();
    return _allCities.where((c) => c.name.toLowerCase().contains(q)).toList();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollCtrl) {
        return Column(
          children: [
            // Заголовок
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                'Выберите город',
                style: GoogleFonts.poppins(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            // Поиск
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                autofocus: false,
                decoration: InputDecoration(
                  hintText: 'Поиск города...',
                  hintStyle: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.grey.shade500,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: Colors.grey.shade500,
                  ),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                ),
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
            ),
            const Divider(height: 1),
            // Список
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                itemCount: filtered.length + 1, // +1 для «Весь Казахстан»
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _CityTile(
                      name: 'Весь Казахстан',
                      icon: Icons.public_rounded,
                      isSelected: widget.currentCity == null,
                      isRegion: false,
                      onTap: () => Navigator.pop(context, const _R(null)),
                    );
                  }
                  final item = filtered[index - 1];
                  return _CityTile(
                    name: item.name,
                    icon: item.isRegion
                        ? Icons.map_outlined
                        : Icons.location_city_rounded,
                    isSelected: widget.currentCity == item.name,
                    isRegion: item.isRegion,
                    onTap: () => Navigator.pop(context, _R(item.name)),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CityItem {
  const _CityItem({required this.name, required this.isRegion});
  final String name;
  final bool isRegion;
}

class _CityTile extends StatelessWidget {
  const _CityTile({
    required this.name,
    required this.icon,
    required this.isSelected,
    required this.isRegion,
    required this.onTap,
  });

  final String name;
  final IconData icon;
  final bool isSelected;
  final bool isRegion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected
                  ? Colors.black87
                  : (isRegion ? Colors.blueGrey.shade400 : Colors.grey.shade500),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: isSelected || isRegion
                      ? FontWeight.w600
                      : FontWeight.w400,
                  color: isSelected ? Colors.black87 : Colors.black87,
                ),
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle_rounded,
                size: 20,
                color: Colors.black87,
              ),
          ],
        ),
      ),
    );
  }
}
