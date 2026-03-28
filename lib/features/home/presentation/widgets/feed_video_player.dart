import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Управляемый видеоплеер для ленты публикаций.
///
/// [isActive] — если true, видео автоматически воспроизводится.
/// При смене страницы в PageView — передавай false для неактивных.
///
/// Пример:
/// ```dart
/// FeedVideoPlayer(
///   videoUrl: post.videoUrl!,
///   isActive: _currentPage == index,
///   aspectRatio: 9 / 16,
/// )
/// ```
class FeedVideoPlayer extends StatefulWidget {
  const FeedVideoPlayer({
    super.key,
    required this.videoUrl,
    this.isActive = false,
    this.aspectRatio,
    this.showControls = true,
    this.looping = true,
    this.onTap,
  });

  final String videoUrl;

  /// Управляет авто-воспроизведением: true = play, false = pause.
  final bool isActive;

  /// Если null — использует оригинальное соотношение видео.
  final double? aspectRatio;

  /// Показывать кнопку play/pause при тапе.
  final bool showControls;

  /// Зациклить видео (для ленты — обычно true).
  final bool looping;

  /// Дополнительный обработчик тапа.
  final VoidCallback? onTap;

  @override
  State<FeedVideoPlayer> createState() => _FeedVideoPlayerState();
}

class _FeedVideoPlayerState extends State<FeedVideoPlayer> {
  late VideoPlayerController _controller;
  bool _initialized = false;
  bool _error = false;
  bool _showPlayIcon = false;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  Future<void> _initController() async {
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.videoUrl),
    );

    try {
      await _controller.initialize();
      _controller.setLooping(widget.looping);
      _controller.setVolume(0); // muted по умолчанию как в Instagram

      if (mounted) {
        setState(() => _initialized = true);
        if (widget.isActive) _controller.play();
      }
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  void didUpdateWidget(FeedVideoPlayer old) {
    super.didUpdateWidget(old);
    if (!_initialized) return;

    // Авто-play/pause при смене активной страницы
    if (widget.isActive != old.isActive) {
      if (widget.isActive) {
        _controller.play();
      } else {
        _controller.pause();
        // Сбрасываем позицию для «свежего» просмотра при возврате
        _controller.seekTo(Duration.zero);
      }
    }

    // Видео сменилось (нужно пересоздать контроллер)
    if (widget.videoUrl != old.videoUrl) {
      _controller.dispose();
      setState(() {
        _initialized = false;
        _error = false;
      });
      _initController();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleMute() {
    if (!_initialized) return;
    final isMuted = _controller.value.volume == 0;
    _controller.setVolume(isMuted ? 1.0 : 0);
    setState(() {});
  }

  void _togglePlay() {
    if (!_initialized) return;
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
        _showPlayIcon = true;
      } else {
        _controller.play();
        _showPlayIcon = false;
      }
    });

    // Скрываем иконку паузы через секунду
    if (_showPlayIcon) {
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) setState(() => _showPlayIcon = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error) return const _VideoErrorPlaceholder();

    if (!_initialized) {
      return const AspectRatio(
        aspectRatio: 9 / 16,
        child: ColoredBox(
          color: Colors.black,
          child: Center(
            child: CircularProgressIndicator(
              color: Colors.white54,
              strokeWidth: 2,
            ),
          ),
        ),
      );
    }

    final ratio = widget.aspectRatio ?? _controller.value.aspectRatio;

    return GestureDetector(
      onTap: () {
        _togglePlay();
        widget.onTap?.call();
      },
      child: AspectRatio(
        aspectRatio: ratio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Само видео
            VideoPlayer(_controller),

            // Прогресс-бар снизу
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: VideoProgressIndicator(
                _controller,
                allowScrubbing: false,
                colors: const VideoProgressColors(
                  playedColor: Colors.white,
                  bufferedColor: Colors.white30,
                  backgroundColor: Colors.transparent,
                ),
                padding: EdgeInsets.zero,
              ),
            ),

            // Иконка паузы/плея при тапе
            if (widget.showControls && _showPlayIcon)
              AnimatedOpacity(
                opacity: _showPlayIcon ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: const BoxDecoration(
                    color: Colors.black45,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _controller.value.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
              ),

            // Кнопка mute/unmute в правом нижнем углу
            Positioned(
              bottom: 12,
              right: 12,
              child: GestureDetector(
                onTap: _toggleMute,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    _controller.value.volume == 0
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoErrorPlaceholder extends StatelessWidget {
  const _VideoErrorPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const AspectRatio(
      aspectRatio: 9 / 16,
      child: ColoredBox(
        color: Color(0xFF1A1A1A),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.videocam_off_rounded, color: Colors.white38, size: 40),
            SizedBox(height: 8),
            Text(
              'Не удалось загрузить видео',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
