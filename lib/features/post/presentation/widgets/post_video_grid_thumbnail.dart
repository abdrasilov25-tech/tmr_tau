import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get_thumbnail_video/index.dart';
import 'package:get_thumbnail_video/video_thumbnail.dart';

/// Кадр-превью сетки для видео по URL (Reels / профиль).
class PostVideoGridThumbnail extends StatefulWidget {
  const PostVideoGridThumbnail({
    super.key,
    required this.videoUrl,
    required this.memCacheWidth,
  });

  final String videoUrl;
  final int memCacheWidth;

  @override
  State<PostVideoGridThumbnail> createState() => _PostVideoGridThumbnailState();
}

class _PostVideoGridThumbnailState extends State<PostVideoGridThumbnail> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant PostVideoGridThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl ||
        oldWidget.memCacheWidth != widget.memCacheWidth) {
      _bytes = null;
      _failed = false;
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final url = widget.videoUrl.trim();
    if (url.isEmpty) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    try {
      final data = await VideoThumbnail.thumbnailData(
        video: url,
        imageFormat: ImageFormat.JPEG,
        maxWidth: widget.memCacheWidth.clamp(64, 640),
        quality: 50,
      );
      if (!mounted) return;
      if (data.isNotEmpty) {
        setState(() {
          _bytes = data;
          _failed = false;
        });
      } else {
        setState(() => _failed = true);
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _placeholder(),
      );
    }
    if (_failed) return _placeholder();
    return const ColoredBox(
      color: Color(0xFFE2E8F0),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return ColoredBox(
      color: Colors.grey.shade300,
      child: const Center(
        child: Icon(Icons.videocam, size: 40, color: Colors.white70),
      ),
    );
  }
}
