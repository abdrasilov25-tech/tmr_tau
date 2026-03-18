import 'package:flutter/foundation.dart';

import 'domain/theme_repository.dart';

/// Состояние темы: индекс и путь к своей картинке.
class _ThemeState {
  _ThemeState(this.index, this.customImagePath);
  final int index;
  final String? customImagePath;
}

/// Хранит индекс темы и путь к своей картинке. При изменении сохраняет через
/// [ThemeRepository]. Для подписки используйте [listenable] в ListenableBuilder.
class ThemeIndexNotifier {
  ThemeIndexNotifier(this._repository)
      : _state = ValueNotifier<_ThemeState>(
          _ThemeState(
            _repository.getThemeIndex(),
            _repository.getCustomThemeImagePath(),
          ),
        ) {
    listenable = _state;
    if (kDebugMode) {
      debugPrint(
        '[ThemeIndexNotifier] init index=${_state.value.index}, path=${_state.value.customImagePath}',
      );
    }
  }

  final ThemeRepository _repository;
  final ValueNotifier<_ThemeState> _state;
  late final Listenable listenable;

  int get value => _state.value.index;
  String? get customImagePath => _state.value.customImagePath;

  void _emitState() {
    _state.value = _ThemeState(
      _repository.getThemeIndex(),
      _repository.getCustomThemeImagePath(),
    );
    if (kDebugMode) {
      debugPrint(
        '[ThemeIndexNotifier] emit index=${_state.value.index}, path=${_state.value.customImagePath}',
      );
    }
  }

  /// Установить пресет (0–5). Своя тема сбрасывается.
  Future<void> setIndex(int index) async {
    final clamped = index.clamp(0, 5);
    if (_state.value.index == clamped &&
        _state.value.customImagePath == null) return;
    await _repository.setPresetTheme(clamped);
    _emitState();
  }

  /// Установить свою тему из байтов изображения (галерея). Индекс становится 6.
  Future<void> setCustomThemeFromImageBytes(List<int> imageBytes) async {
    await _repository.setCustomThemeFromImageBytes(imageBytes);
    _emitState();
  }
}
