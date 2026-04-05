/// Доп. аргумент при открытии [StoryCameraPage] через GoRouter `extra`.
class StoryCameraStartIntent {
  const StoryCameraStartIntent({this.recordVideoOnOpen = false});

  /// После инициализации камеры сразу начать запись видео.
  final bool recordVideoOnOpen;
}
