import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/login_theme_presets.dart';

/// Нижняя панель выбора темы фона (как на экране входа и в главном shell).
/// [currentIndex] — сохранённый индекс (0–6), [onSelect] — при выборе пресета,
/// [onAddCustom] — при нажатии «Добавить» (загрузка своей темы из галереи).
void showThemePickerSheet(
  BuildContext context, {
  required int currentIndex,
  required ValueChanged<int> onSelect,
  Future<void> Function()? onAddCustom,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => ThemePickerSheet(
      currentIndex: currentIndex,
      onSelect: (index) {
        onSelect(index);
        Navigator.of(context).pop();
      },
      onAddCustom: onAddCustom,
    ),
  );
}

class ThemePickerSheet extends StatelessWidget {
  const ThemePickerSheet({
    super.key,
    required this.currentIndex,
    required this.onSelect,
    this.onAddCustom,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;
  final Future<void> Function()? onAddCustom;

  static const List<(String label, List<Color> colors)> _options = [
    ('Neon', LoginThemePresets.neon),
    ('Обычный', LoginThemePresets.ordinary),
    ('Синий градиент', LoginThemePresets.blue),
    ('Pink', LoginThemePresets.pink),
    ('Purple', LoginThemePresets.purple),
    ('Dark', LoginThemePresets.dark),
  ];

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.7;
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: Color(0xFF252530),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF6B6B80),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Темки',
              style: GoogleFonts.poppins(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Фон экрана входа и главного экрана',
              style: GoogleFonts.poppins(
                fontSize: 15,
                color: Color(0xFFB0B0C0),
              ),
            ),
            const SizedBox(height: 24),
            if (onAddCustom != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _AddCustomTile(
                  isSelected: currentIndex == 6,
                  onTap: () async {
                    await onAddCustom!();
                    if (context.mounted) Navigator.of(context).pop();
                  },
                ),
              ),
            ...List.generate(_options.length, (index) {
            final selected = index == currentIndex;
            final option = _options[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: selected ? const Color(0xFF3A3A4A) : const Color(0xFF2E2E3A),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  onTap: () => onSelect(index),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF6C9EFF)
                            : const Color(0xFF404055),
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: option.$2,
                            ),
                            border: Border.all(
                              color: const Color(0xFF505065),
                              width: 1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Text(
                            option.$1,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 17,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        if (selected)
                          const Icon(
                            Icons.check_circle_rounded,
                            color: Color(0xFF6C9EFF),
                            size: 26,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
          ],
        ),
      ),
    );
  }
}

class _AddCustomTile extends StatelessWidget {
  const _AddCustomTile({
    required this.isSelected,
    required this.onTap,
  });

  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? const Color(0xFF3A3A4A) : const Color(0xFF2E2E3A),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? const Color(0xFF6C9EFF) : const Color(0xFF404055),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF404055),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.add_photo_alternate, color: Colors.white70, size: 26),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Text(
                  'Добавить',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 17,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              ),
              if (isSelected)
                const Icon(Icons.check_circle_rounded, color: Color(0xFF6C9EFF), size: 26),
            ],
          ),
        ),
      ),
    );
  }
}
