import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// До [remainingSlots] файлов: сначала выбор «Галерея» или «Камера», затем [ImagePicker].
Future<List<XFile>> pickProductImageFiles(
  BuildContext context, {
  required int remainingSlots,
}) async {
  if (remainingSlots <= 0) return [];
  if (!context.mounted) return [];

  final source = await showModalBottomSheet<ImageSource?>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Галерея'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Камера'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
        ],
      ),
    ),
  );

  if (source == null || !context.mounted) return [];

  final picker = ImagePicker();
  if (source == ImageSource.gallery) {
    final list = await picker.pickMultiImage(imageQuality: 85);
    if (list.length <= remainingSlots) return list;
    return list.take(remainingSlots).toList();
  }

  final file = await picker.pickImage(
    source: ImageSource.camera,
    imageQuality: 85,
  );
  return file == null ? <XFile>[] : <XFile>[file];
}
