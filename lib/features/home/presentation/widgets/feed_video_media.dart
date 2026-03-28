import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../post/presentation/widgets/post_photo_gallery.dart';

enum _MediaPlaceholderType { neutral, photo }

class _MediaPlaceholder extends StatelessWidget {
  const _MediaPlaceholder({required this.type});

  final _MediaPlaceholderType type;

  @override
  Widget build(BuildContext context) {
    final text =
        type == _MediaPlaceholderType.photo ? 'Фото-заглушка' : 'Медиа-заглушка';
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_outlined,
                color: Colors.white.withValues(alpha: 0.7), size: 56),
            const SizedBox(height: 10),
            Text(
              text,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Публичный виджет: показывает видео или фото-галерею.
class FeedPostMedia extends StatelessWidget {
  const FeedPostMedia({
    super.key,
    required this.imageUrls,
    required this.videoUrl,
    required this.fillHeight,
  });

  final List<String> imageUrls;
  final String? videoUrl;
  final double fillHeight;

  @override
  Widget build(BuildContext context) {
    if (videoUrl != null && videoUrl!.isNotEmpty) {
      return FeedVideoMedia(videoUrl: videoUrl!);
    }

    if (imageUrls.isNotEmpty) {
      return PostNetworkPhotoGallery(
        urls: imageUrls,
        height: fillHeight,
        borderRadius: 0,
        viewportFraction: imageUrls.length > 1 ? 0.9 : 1,
      );
    }

    return _MediaPlaceholder(type: _MediaPlaceholderType.neutral);
  }
}

/// Публичный виджет: воспроизводит видео в цикле с обработкой ошибок.
class FeedVideoMedia extends StatefulWidget {
  const FeedVideoMedia({super.key, required this.videoUrl});

  final String videoUrl;

  @override
  State<FeedVideoMedia> createState() => _FeedVideoMediaState();
}

class _FeedVideoMediaState extends State<FeedVideoMedia> {
  late final VideoPlayerController _controller;
  bool _ready = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..setLooping(true)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _ready = true);
        _controller.play();
      }).catchError((_) {
        if (mounted) setState(() => _hasError = true);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Icon(Icons.videocam_off_outlined,
              color: Colors.white54, size: 48),
        ),
      );
    }
    if (!_ready) {
      return const Center(child: CircularProgressIndicator());
    }
    final size = _controller.value.size;
    if (size.width <= 0 || size.height <= 0) {
      return const Center(child: CircularProgressIndicator());
    }
    return SizedBox.expand(
      child: ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() {
                  if (_controller.value.isPlaying) {
                    _controller.pause();
                  } else {
                    _controller.play();
                  }
                });
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  VideoPlayer(_controller),
                  if (!_controller.value.isPlaying)
                    const Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(14),
                          child: Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 38,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
