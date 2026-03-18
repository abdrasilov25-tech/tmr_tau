import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../storage/local_reactions_storage.dart';
import '../domain/theme_repository.dart';

class ThemeRepositoryImpl implements ThemeRepository {
  ThemeRepositoryImpl(this._storage);

  final LocalReactionsStorage _storage;

  static const _customThemePrefix = 'custom_theme_';

  @override
  int getThemeIndex() => _storage.getLoginThemeIndex();

  @override
  String? getCustomThemeImagePath() => _storage.getCustomThemeImagePath();

  @override
  Future<void> setPresetTheme(int index) async {
    final clamped = index.clamp(0, 5);
    final oldPath = _storage.getCustomThemeImagePath();
    if (oldPath != null) {
      try {
        final f = File(oldPath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    await _storage.setCustomThemeImagePath(null);
    await _storage.setLoginThemeIndex(clamped);
    if (kDebugMode) {
      debugPrint('[ThemeRepositoryImpl] setPresetTheme clamped=$clamped');
    }
  }

  @override
  Future<void> setCustomThemeFromImageBytes(List<int> imageBytes) async {
    final dir = await getApplicationDocumentsDirectory();
    final themeDir = Directory('${dir.path}/theme');
    if (!await themeDir.exists()) {
      await themeDir.create(recursive: true);
    }
    final oldPath = _storage.getCustomThemeImagePath();
    if (oldPath != null) {
      try {
        final f = File(oldPath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    final fileName =
        '${_customThemePrefix}${DateTime.now().millisecondsSinceEpoch}.jpg';
    final file = File('${themeDir.path}/$fileName');
    await file.writeAsBytes(imageBytes);
    final absolutePath = file.absolute.path;
    await _storage.setCustomThemeImagePath(absolutePath);
    await _storage.setLoginThemeIndex(6);
    if (kDebugMode) {
      debugPrint(
        '[ThemeRepositoryImpl] setCustomThemeFromImageBytes path=$absolutePath',
      );
    }
  }
}
