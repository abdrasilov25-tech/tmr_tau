import 'dart:io';

import 'package:flutter/material.dart';

import 'login_theme_presets.dart';

/// Строит [BoxDecoration] фона по индексу темы и опциональному пути к своей картинке.
/// Индекс 6 + непустой [customImagePath] — своя тема из галереи.
BoxDecoration themeDecoration(int themeIndex, String? customImagePath) {
  if (themeIndex == 6 &&
      customImagePath != null &&
      customImagePath.isNotEmpty) {
    final file = File(customImagePath);
    final exists = file.existsSync();
    if (exists) {
      return BoxDecoration(
        image: DecorationImage(
          image: FileImage(file),
          fit: BoxFit.cover,
        ),
      );
    }
  }

  return LoginThemePresets.gradientDecoration(themeIndex.clamp(0, 5));
}
