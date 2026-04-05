import 'dart:async';
import 'dart:io';
import 'dart:math' show min;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/entities/story_overlay_item.dart';

/// Отрисовка стикеров поверх кадра 9:16 (редактор или просмотр).
class StoryOverlaysStack extends StatelessWidget {
  const StoryOverlaysStack({
    super.key,
    required this.items,
    this.editable = false,
    this.onPositionChanged,
    this.onRemove,
  });

  final List<StoryOverlayItem> items;
  final bool editable;
  final void Function(int index, double nx, double ny)? onPositionChanged;
  final void Function(int index)? onRemove;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fw = constraints.maxWidth;
        final fh = constraints.maxHeight;
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < items.length; i++)
              _OverlayEntry(
                key: ValueKey<String>(items[i].id),
                item: items[i],
                frameW: fw,
                frameH: fh,
                editable: editable,
                onPanUpdate: editable && onPositionChanged != null
                    ? (dx, dy) {
                        onPositionChanged!(
                          i,
                          (items[i].nx + dx / fw).clamp(0.06, 0.94),
                          (items[i].ny + dy / fh).clamp(0.06, 0.94),
                        );
                      }
                    : null,
                onLongPress: editable && onRemove != null
                    ? () => onRemove!(i)
                    : null,
              ),
          ],
        );
      },
    );
  }
}

class _OverlayEntry extends StatelessWidget {
  const _OverlayEntry({
    super.key,
    required this.item,
    required this.frameW,
    required this.frameH,
    required this.editable,
    this.onPanUpdate,
    this.onLongPress,
  });

  final StoryOverlayItem item;
  final double frameW;
  final double frameH;
  final bool editable;
  final void Function(double dx, double dy)? onPanUpdate;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    Widget child = _buildBody(context);
    if (editable && (onPanUpdate != null || onLongPress != null)) {
      child = GestureDetector(
        onPanUpdate:
            onPanUpdate == null ? null : (d) => onPanUpdate!(d.delta.dx, d.delta.dy),
        onLongPress: onLongPress,
        child: child,
      );
    }
    return Align(
      alignment: Alignment(
        item.nx * 2 - 1,
        item.ny * 2 - 1,
      ),
      child: child,
    );
  }

  Widget _buildBody(BuildContext context) {
    final d = item.data;
    switch (item.type) {
      case 'text':
        return _chip(
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: frameW * 0.85),
            child: Text(
              d['text'] as String? ?? '',
              style: TextStyle(
                color: Color(d['color'] as int? ?? 0xFFFFFFFF),
                fontWeight: FontWeight.w800,
                fontSize: 22,
                shadows: const [
                  Shadow(color: Colors.black54, blurRadius: 6),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        );
      case 'hashtag':
        return _chip(
          Text(
            '#${d['tag'] as String? ?? ''}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
              shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
            ),
          ),
        );
      case 'mention':
        return _chip(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.orange.shade700,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '@${d['username'] as String? ?? ''}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        );
      case 'link':
        return Material(
          color: Colors.blue.shade700,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: () async {
              final url = d['url'] as String? ?? '';
              final u = Uri.tryParse(url);
              if (u != null && await canLaunchUrl(u)) {
                await launchUrl(u, mode: LaunchMode.externalApplication);
              }
            },
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.link_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    d['title'] as String? ?? 'Ссылка',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      case 'location':
        return _chip(
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: frameW * 0.75),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.location_on_rounded, color: Colors.purple.shade200),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    d['label'] as String? ?? '',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      case 'poll':
        return Container(
          constraints: BoxConstraints(maxWidth: frameW * 0.72),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.purple.shade900.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                d['question'] as String? ?? '',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              _pollLine(d['optionA'] as String? ?? 'A'),
              const SizedBox(height: 8),
              _pollLine(d['optionB'] as String? ?? 'B'),
            ],
          ),
        );
      case 'question':
        return Container(
          constraints: BoxConstraints(maxWidth: frameW * 0.72),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.purple.shade600,
                Colors.pink.shade600,
              ],
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.chat_bubble_outline, color: Colors.white, size: 22),
              const SizedBox(height: 8),
              Text(
                d['prompt'] as String? ?? '',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Ответ…',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        );
      case 'countdown':
        return _CountdownSticker(
          untilIso: d['until'] as String? ?? '',
          title: d['title'] as String? ?? '',
        );
      case 'image':
      case 'gif':
        final url = d['url'] as String?;
        final path = d['localPath'] as String?;
        if (url != null && url.isNotEmpty) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: CachedNetworkImage(
              imageUrl: url,
              width: 120,
              height: 120,
              fit: BoxFit.cover,
            ),
          );
        }
        if (path != null && File(path).existsSync()) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(
              File(path),
              width: 120,
              height: 120,
              fit: BoxFit.cover,
            ),
          );
        }
        return const SizedBox.shrink();
      case 'add_yours':
        return Container(
          constraints: BoxConstraints(maxWidth: frameW * 0.7),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.pink.shade700.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Ваш ответ',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                d['prompt'] as String? ?? '',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
        );
      case 'frame':
        return Container(
          width: min(200.0, frameW * 0.5),
          height: min(260.0, frameH * 0.45),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            boxShadow: const [
              BoxShadow(color: Colors.black45, blurRadius: 12),
            ],
          ),
          child: const Center(
            child: Icon(Icons.photo_outlined, size: 48, color: Colors.black26),
          ),
        );
      case 'notify':
        return _chip(
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: frameW * 0.7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.notifications_active_rounded, color: Colors.white),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        d['title'] as String? ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        d['subtitle'] as String? ?? '',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      case 'slider':
        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: frameW * 0.75),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  d['emoji'] as String? ?? '❤️',
                  style: const TextStyle(fontSize: 28),
                ),
                Text(
                  d['label'] as String? ?? '',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                IgnorePointer(
                  ignoring: !editable,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 10),
                    ),
                    child: Slider(
                      value: (d['value'] as num?)?.toDouble() ?? 0.5,
                      onChanged: (_) {},
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      case 'food':
        return Material(
          color: Colors.red.shade800,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: () async {
              final t = d['title'] as String? ?? '';
              final u = Uri.tryParse(t.trim());
              if (u != null &&
                  u.hasScheme &&
                  await canLaunchUrl(u)) {
                await launchUrl(u, mode: LaunchMode.externalApplication);
              }
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.delivery_dining_rounded, color: Colors.white),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      d['title'] as String? ?? '',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      case 'avatar':
        final u = d['url'] as String? ?? '';
        if (u.isEmpty) return const SizedBox.shrink();
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [
              BoxShadow(color: Colors.black38, blurRadius: 8),
            ],
          ),
          child: ClipOval(
            child: CachedNetworkImage(
              imageUrl: u,
              width: 72,
              height: 72,
              fit: BoxFit.cover,
            ),
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _pollLine(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _chip(Widget w) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: w,
    );
  }
}

class _CountdownSticker extends StatefulWidget {
  const _CountdownSticker({
    required this.untilIso,
    required this.title,
  });

  final String untilIso;
  final String title;

  @override
  State<_CountdownSticker> createState() => _CountdownStickerState();
}

class _CountdownStickerState extends State<_CountdownSticker> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    DateTime? until;
    try {
      until = DateTime.parse(widget.untilIso);
    } catch (_) {
      return const SizedBox.shrink();
    }
    final now = DateTime.now();
    final diff = until.difference(now);
    String label;
    if (diff.isNegative) {
      label = '0:00:00';
    } else {
      final h = diff.inHours;
      final m = diff.inMinutes.remainder(60);
      final s = diff.inSeconds.remainder(60);
      label =
          '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.deepPurple.shade800.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.title,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 22,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
