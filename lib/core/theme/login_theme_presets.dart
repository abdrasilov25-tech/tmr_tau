import 'package:flutter/material.dart';

/// Пресеты градиентов для экрана входа и фона приложения после входа.
/// Индекс темы сохраняется в LocalReactionsStorage (getLoginThemeIndex).
class LoginThemePresets {
  LoginThemePresets._();

  static const List<Color> neon = [
    Color(0xFF6B2D9E),
    Color(0xFF8B2D9E),
    Color(0xFFE91E8C),
    Color(0xFFE85A4F),
    Color(0xFFFF6B35),
    Color(0xFFFFA726),
    Color(0xFFFFD23F),
    Color(0xFF26C6DA),
    Color(0xFF00D9D9),
  ];

  static const List<Color> blue = [
    Color(0xFF0D47A1),
    Color(0xFF1565C0),
    Color(0xFF1976D2),
    Color(0xFF42A5F5),
    Color(0xFF64B5F6),
    Color(0xFF90CAF9),
    Color(0xFFBBDEFB),
    Color(0xFF4FC3F7),
    Color(0xFF00BCD4),
  ];

  static const List<Color> pink = [
    Color(0xFF880E4F),
    Color(0xFFAD1457),
    Color(0xFFC2185B),
    Color(0xFFE91E63),
    Color(0xFFF06292),
    Color(0xFFF48FB1),
    Color(0xFFF8BBD9),
    Color(0xFFEC407A),
    Color(0xFFF50057),
  ];

  static const List<Color> purple = [
    Color(0xFF4A148C),
    Color(0xFF6A1B9A),
    Color(0xFF7B1FA2),
    Color(0xFF9C27B0),
    Color(0xFFAB47BC),
    Color(0xFFCE93D8),
    Color(0xFFE1BEE7),
    Color(0xFF7C4DFF),
    Color(0xFF651FFF),
  ];

  static const List<Color> dark = [
    Color(0xFF1A1A2E),
    Color(0xFF16213E),
    Color(0xFF0F3460),
    Color(0xFF1B262C),
    Color(0xFF2C3E50),
    Color(0xFF34495E),
    Color(0xFF2D3436),
    Color(0xFF6C5CE7),
    Color(0xFF00CEC9),
  ];

  static const List<Color> ordinary = [
    Color(0xFFFFFFFF),
    Color(0xFFFAFAFA),
    Color(0xFFF5F5F5),
    Color(0xFFF0F0F0),
    Color(0xFFEEEEEE),
    Color(0xFFE8E8E8),
    Color(0xFFE0E0E0),
    Color(0xFFF5F5F5),
    Color(0xFFFAFAFA),
  ];

  static const List<double> _stops = [0.0, 0.2, 0.35, 0.5, 0.6, 0.75, 0.85, 0.92, 1.0];

  static List<Color> preset(int index) {
    switch (index) {
      case 0: return neon;
      case 1: return ordinary;
      case 2: return blue;
      case 3: return pink;
      case 4: return purple;
      case 5: return dark;
      default: return neon;
    }
  }

  static BoxDecoration gradientDecoration(int themeIndex) {
    final colors = preset(themeIndex);
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
        stops: _stops,
      ),
    );
  }
}
