import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:video_player/video_player.dart';

/// Загружает видео по HTTP(S) через [DefaultCacheManager]: повторный просмотр идёт с диска.
Future<VideoPlayerController> createCachedVideoController(String url) async {
  final trimmed = url.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError('Пустой URL видео');
  }
  final uri = Uri.parse(trimmed);
  if (uri.scheme == 'file') {
    return VideoPlayerController.file(File.fromUri(uri));
  }
  final file = await DefaultCacheManager().getSingleFile(trimmed);
  return VideoPlayerController.file(file);
}
