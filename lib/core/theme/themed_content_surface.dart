import 'package:flutter/material.dart';

/// Непрозрачный фон основного контента поверх тематического градиента/фото,
/// чтобы поля и текст не сливались с фоном.
abstract final class ThemedContentSurface {
  static const Color scaffold = Color(0xFFF4F5F8);
  static const Color scaffoldElevated = Color(0xFFFFFFFF);

  /// Панель на экране входа (читаемость на любом фоне темы).
  static Color get loginPanel => Colors.white.withValues(alpha: 0.94);

  /// Карточка поверх тематического фона (профиль, формы).
  static BoxDecoration profileCardDecoration({double radius = 20}) =>
      BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 28,
            offset: const Offset(0, 10),
            spreadRadius: -4,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      );

  /// Одна большая карточка профиля (скругление снизу для сетки).
  static const double profileUnifiedRadius = 26;

  static const Color profileTextPrimary = Color(0xFF1A1A1E);
  static const Color profileTextSecondary = Color(0xFF4A4A55);
}
