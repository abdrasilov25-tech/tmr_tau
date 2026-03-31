import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:video_player/video_player.dart';

/// Воспроизводит видео: если файл закэширован — с диска (мгновенно),
/// иначе — стриминг по сети (без ожидания полной загрузки).
Future<VideoPlayerController> createCachedVideoController(String url) async {
  final trimmed = url.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError('Пустой URL видео');
  }
  final uri = Uri.parse(trimmed);
  if (uri.scheme == 'file') {
    return VideoPlayerController.file(File.fromUri(uri));
  }
  final cachedFile = await DefaultCacheManager().getFileFromCache(trimmed);
  if (cachedFile != null) {
    return VideoPlayerController.file(cachedFile.file);
  }
  return VideoPlayerController.networkUrl(uri);
}
