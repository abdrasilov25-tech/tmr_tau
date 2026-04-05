import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/story_overlay_item.dart';

const _uuid = Uuid();

/// Диалоги и действия для стикеров листа (как в Instagram).
class StoryStickerPickHelpers {
  StoryStickerPickHelpers._();

  static StoryOverlayItem _base(String type, Map<String, dynamic> data,
      {double nx = 0.5, double ny = 0.42}) {
    return StoryOverlayItem(
      id: _uuid.v4(),
      type: type,
      nx: nx,
      ny: ny,
      data: data,
    );
  }

  static Future<String?> _promptText(
    BuildContext context, {
    required String title,
    required String hint,
    int maxLines = 1,
  }) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2E),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: maxLines,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade500),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Готово'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return null;
    final t = ctrl.text.trim();
    return t.isEmpty ? null : t;
  }

  static Future<StoryOverlayItem?> addText(BuildContext context) async {
    final t = await _promptText(context, title: 'Текст', hint: 'Введите текст');
    if (t == null) return null;
    return _base('text', {'text': t, 'color': 0xFFFFFFFF});
  }

  static Future<StoryOverlayItem?> addHashtag(BuildContext context) async {
    final t = await _promptText(context, title: '#хэштег', hint: 'travel');
    if (t == null) return null;
    final tag = t.startsWith('#') ? t.substring(1) : t;
    return _base('hashtag', {'tag': tag});
  }

  static Future<StoryOverlayItem?> addMention(BuildContext context) async {
    final t = await _promptText(context, title: '@упоминание', hint: 'username');
    if (t == null) return null;
    final u = t.startsWith('@') ? t.substring(1) : t;
    return _base('mention', {'username': u});
  }

  static Future<StoryOverlayItem?> addLink(BuildContext context) async {
    final url = await _promptText(
      context,
      title: 'Ссылка',
      hint: 'https://…',
    );
    if (url == null) return null;
    var u = url.trim();
    if (!u.startsWith('http')) u = 'https://$u';
    return _base('link', {'url': u, 'title': 'Ссылка'});
  }

  static Future<StoryOverlayItem?> addPoll(BuildContext context) async {
    final qCtrl = TextEditingController();
    final aCtrl = TextEditingController(text: 'Да');
    final bCtrl = TextEditingController(text: 'Нет');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2E),
        title: const Text('Опрос', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: qCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Вопрос',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
              ),
              TextField(
                controller: aCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Вариант 1',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
              ),
              TextField(
                controller: bCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Вариант 2',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Готово'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return null;
    final q = qCtrl.text.trim();
    if (q.isEmpty) return null;
    return _base('poll', {
      'question': q,
      'optionA': aCtrl.text.trim().isEmpty ? 'Да' : aCtrl.text.trim(),
      'optionB': bCtrl.text.trim().isEmpty ? 'Нет' : bCtrl.text.trim(),
    });
  }

  static Future<StoryOverlayItem?> addQuestion(BuildContext context) async {
    final t = await _promptText(
      context,
      title: 'Вопрос',
      hint: 'Спросите подписчиков…',
      maxLines: 3,
    );
    if (t == null) return null;
    return _base('question', {'prompt': t});
  }

  static Future<StoryOverlayItem?> addCountdown(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (picked == null || !context.mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    if (time == null || !context.mounted) return null;
    final until = DateTime(
      picked.year,
      picked.month,
      picked.day,
      time.hour,
      time.minute,
    );
    final title = await _promptText(
      context,
      title: 'Подпись таймера',
      hint: 'Новый год',
    );
    return _base('countdown', {
      'until': until.toIso8601String(),
      'title': title ?? 'Событие',
    });
  }

  static Future<StoryOverlayItem?> addLocation(BuildContext context) async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever ||
        perm == LocationPermission.denied) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нужен доступ к геолокации')),
        );
      }
      return null;
    }
    final pos = await Geolocator.getCurrentPosition();
    String label = '${pos.latitude.toStringAsFixed(4)}, '
        '${pos.longitude.toStringAsFixed(4)}';
    try {
      final marks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (marks.isNotEmpty) {
        final p = marks.first;
        final parts = <String>[];
        for (final x in [p.locality, p.subAdministrativeArea, p.country]) {
          if (x != null && x.trim().isNotEmpty) parts.add(x.trim());
        }
        if (parts.isNotEmpty) {
          label = parts.take(2).join(', ');
        }
      }
    } catch (_) {}
    return _base('location', {
      'label': label,
      'lat': pos.latitude,
      'lng': pos.longitude,
    });
  }

  static Future<StoryOverlayItem?> addPhotoSticker(BuildContext context) async {
    final p = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (p == null) return null;
    final lower = p.path.toLowerCase();
    final type = lower.endsWith('.gif') ? 'gif' : 'image';
    return _base(type, {'localPath': p.path});
  }

  static Future<StoryOverlayItem?> addGifSticker(BuildContext context) async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['gif'],
    );
    if (r == null || r.files.isEmpty) return null;
    final path = r.files.single.path;
    if (path == null) return null;
    return _base('gif', {'localPath': path});
  }

  static Future<StoryOverlayItem?> addAddYours(BuildContext context) async {
    final t = await _promptText(
      context,
      title: 'Ваш ответ',
      hint: 'Покажите своё фото…',
    );
    if (t == null) return null;
    return _base('add_yours', {'prompt': t});
  }

  static StoryOverlayItem addFrame() {
    return _base('frame', {'style': 'polaroid'});
  }

  static Future<StoryOverlayItem?> addNotify(BuildContext context) async {
    final t = await _promptText(
      context,
      title: 'Уведомить',
      hint: 'О чём напомнить?',
    );
    if (t == null) return null;
    return _base('notify', {'title': t, 'subtitle': 'Напоминание'});
  }

  static StoryOverlayItem? addAvatarSticker(String? avatarUrl) {
    if (avatarUrl == null || avatarUrl.trim().isEmpty) return null;
    return _base('avatar', {'url': avatarUrl.trim()}, nx: 0.5, ny: 0.25);
  }

  static Future<StoryOverlayItem?> addSlider(BuildContext context) async {
    final emoji = await _promptText(
      context,
      title: 'Шкала',
      hint: 'Эмодзи (например 🔥)',
    );
    if (emoji == null) return null;
    if (!context.mounted) return null;
    final label = await _promptText(
      context,
      title: 'Подпись',
      hint: 'Оцените',
    );
    return _base('slider', {
      'emoji': emoji,
      'label': label ?? '',
      'value': 0.62,
    });
  }

  static Future<StoryOverlayItem?> addFood(BuildContext context) async {
    final t = await _promptText(
      context,
      title: 'Заказы еды',
      hint: 'Название или ссылка',
    );
    if (t == null) return null;
    return _base('food', {'title': t});
  }

  static Future<StoryOverlayItem?> addCutout(BuildContext context) async {
    return addPhotoSticker(context);
  }

  static Future<StoryOverlayItem?> addTrending(BuildContext context) async {
    final t = await _promptText(
      context,
      title: 'Актуальное',
      hint: '#тема',
    );
    if (t == null) return null;
    var tag = t.trim();
    if (tag.startsWith('#')) tag = tag.substring(1);
    return _base('hashtag', {'tag': tag});
  }
}
