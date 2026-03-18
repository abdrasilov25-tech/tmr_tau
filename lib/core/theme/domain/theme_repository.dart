/// Репозиторий темы фона приложения (пресеты и своя из галереи).
abstract class ThemeRepository {
  /// Текущий индекс темы: 0–5 пресеты, 6 — своя из галереи.
  int getThemeIndex();

  /// Путь к файлу своей темы; null, если не задана.
  String? getCustomThemeImagePath();

  /// Установить пресет по индексу (0–5). Своя тема при этом сбрасывается.
  Future<void> setPresetTheme(int index);

  /// Установить свою тему из байтов изображения (сохраняет в директорию приложения).
  /// Индекс становится 6.
  Future<void> setCustomThemeFromImageBytes(List<int> imageBytes);
}
