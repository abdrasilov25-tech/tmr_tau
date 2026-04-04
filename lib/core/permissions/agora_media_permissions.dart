import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Запрос камеры и микрофона для Agora. При «навсегда отказано» предлагает открыть настройки.
Future<bool> ensureAgoraCameraAndMicrophone(BuildContext context) async {
  final cam = await Permission.camera.request();
  final mic = await Permission.microphone.request();
  if (cam.isGranted && mic.isGranted) return true;

  final permanent =
      cam.isPermanentlyDenied || mic.isPermanentlyDenied;
  if (!context.mounted) return false;

  if (permanent) {
    final open = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Камера и микрофон'),
        content: const Text(
          'Для эфира нужен доступ к камере и микрофону. '
          'Включите их в настройках приложения.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Настройки'),
          ),
        ],
      ),
    );
    if (open == true && context.mounted) {
      await openAppSettings();
    }
  }

  return false;
}
