import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Результат проверки доступа к галерее для сторис.
enum StoryGalleryAccess {
  /// Можно вызывать ImagePicker.
  ok,

  /// Отказ в системном диалоге — без перехода в настройки.
  deniedInDialog,

  /// Доступ заблокирован в настройках ОС — открывать настройки только по кнопке пользователя.
  needsSettings,
}

/// Общая логика разрешений для сторис (галерея / камера), без автоматических циклов в настройки.
abstract final class StoryMediaPermissions {
  StoryMediaPermissions._();

  /// Галерея: фото или видео. Не вызывает [openAppSettings] — только возвращает статус.
  static Future<StoryGalleryAccess> galleryAccess({required bool forVideo}) async {
    if (Platform.isIOS) {
      var s = await Permission.photos.status;
      if (s.isGranted || s.isLimited) return StoryGalleryAccess.ok;
      s = await Permission.photos.request();
      if (s.isGranted || s.isLimited) return StoryGalleryAccess.ok;
      if (s.isPermanentlyDenied) return StoryGalleryAccess.needsSettings;
      return StoryGalleryAccess.deniedInDialog;
    }

    // Android: сначала photos (и для видео — часто достаточно для picker).
    var photos = await Permission.photos.status;
    if (!photos.isGranted && !photos.isLimited) {
      photos = await Permission.photos.request();
    }
    if (!photos.isGranted && !photos.isLimited) {
      if (photos.isPermanentlyDenied) return StoryGalleryAccess.needsSettings;
      return StoryGalleryAccess.deniedInDialog;
    }

    if (!forVideo) return StoryGalleryAccess.ok;

    // Видео: отдельный permission на Android 13+ часто остаётся denied при уже выданных фото —
    // не блокируем галерею: ImagePicker сам запросит при необходимости.
    var videos = await Permission.videos.status;
    if (videos.isGranted || videos.isLimited) return StoryGalleryAccess.ok;
    videos = await Permission.videos.request();
    if (videos.isGranted || videos.isLimited) return StoryGalleryAccess.ok;

    return StoryGalleryAccess.ok;
  }

  /// Явное подтверждение перед переходом в настройки (без повторных автоматических вызовов).
  static Future<void> offerOpenSettings(
    BuildContext context, {
    required String message,
  }) async {
    if (!context.mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Нужен доступ'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Открыть настройки'),
          ),
        ],
      ),
    );
    if (go == true && context.mounted) {
      await openAppSettings();
    }
  }
}
