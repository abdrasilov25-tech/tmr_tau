import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:tmr_tau/core/media/cached_video_controller.dart';
import 'package:tmr_tau/core/media/global_video_audio_state.dart';
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
    /// Заполняет родителя с [BoxFit.cover] (рилсы / полноэкранный фид).
    /// В ленте карточек оставьте false.
    this.coverFullscreen = false,
    /// URL превью трека (iTunes и т.п.): играет вместо звука ролика, в цикле.
    this.musicPreviewUrl,
  });

  final String videoUrl;

  /// Не muxed в файл — отдельный аудиопоток поверх видео.
  final String? musicPreviewUrl;

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

  final bool coverFullscreen;

  @override
  State<FeedVideoPlayer> createState() => _FeedVideoPlayerState();
}

class _FeedVideoPlayerState extends State<FeedVideoPlayer> {
  VideoPlayerController? _controller;
  AudioPlayer? _musicPlayer;
  bool _musicActive = false;
  bool _initialized = false;
  bool _error = false;
  bool _showPlayIcon = false;
  final GlobalVideoAudioState _audioState = GlobalVideoAudioState.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_audioState.ensureLoaded());
    _audioState.isMuted.addListener(_syncVolumeWithGlobalState);
    unawaited(_initController());
  }

  Future<void> _initController() async {
    try {
      final controller = await createCachedVideoController(widget.videoUrl);
      await controller.initialize();
      controller.setLooping(widget.looping);
      controller.setVolume(_audioState.isMuted.value ? 0 : 1);
      if (!mounted) {
        await controller.dispose();
        await _disposeMusicPlayer();
        return;
      }
      _controller = controller;
      setState(() => _initialized = true);

      final track = widget.musicPreviewUrl?.trim();
      if (track != null && track.isNotEmpty) {
        try {
          await _attachMusicTrack(track, controller);
        } catch (_) {
          await controller.setVolume(_audioState.isMuted.value ? 0 : 1);
        }
      } else {
        await _disposeMusicPlayer();
      }

      if (widget.isActive) {
        await controller.play();
        if (_musicActive) await _musicPlayer?.resume();
      }
    } catch (e) {
      if (mounted) setState(() => _error = true);
    }
  }

  Future<void> _attachMusicTrack(String url, VideoPlayerController video) async {
    await _disposeMusicPlayer();
    final player = AudioPlayer();
    await player.setReleaseMode(ReleaseMode.loop);
    await player.setVolume(_audioState.isMuted.value ? 0 : 1);
    await player.setSource(UrlSource(url));
    await video.setVolume(0);
    _musicPlayer = player;
    _musicActive = true;
  }

  Future<void> _disposeMusicPlayer() async {
    _musicActive = false;
    final p = _musicPlayer;
    _musicPlayer = null;
    await p?.dispose();
  }

  @override
  void didUpdateWidget(FeedVideoPlayer old) {
    super.didUpdateWidget(old);
    if (widget.videoUrl != old.videoUrl ||
        widget.musicPreviewUrl != old.musicPreviewUrl) {
      unawaited(_disposeMusicPlayer());
      _controller?.dispose();
      _controller = null;
      setState(() {
        _initialized = false;
        _error = false;
      });
      unawaited(_initController());
      return;
    }
    if (!_initialized) return;
    final c = _controller;
    if (c == null) return;

    if (widget.isActive != old.isActive) {
      if (widget.isActive) {
        c.play();
        if (_musicActive) unawaited(_musicPlayer?.resume());
      } else {
        c.pause();
        c.seekTo(Duration.zero);
        if (_musicActive) unawaited(_musicPlayer?.pause());
      }
    }
  }

  @override
  void dispose() {
    _audioState.isMuted.removeListener(_syncVolumeWithGlobalState);
    unawaited(_disposeMusicPlayer());
    _controller?.dispose();
    super.dispose();
  }

  void _syncVolumeWithGlobalState() {
    final c = _controller;
    if (c == null || !_initialized) return;
    final muted = _audioState.isMuted.value;
    if (_musicActive) {
      c.setVolume(0);
      _musicPlayer?.setVolume(muted ? 0 : 1);
    } else {
      c.setVolume(muted ? 0 : 1);
    }
    if (mounted) setState(() {});
  }

  void _toggleMute() {
    unawaited(_audioState.toggle());
  }

  void _togglePlay() {
    final c = _controller;
    if (!_initialized || c == null) return;
    setState(() {
      if (c.value.isPlaying) {
        c.pause();
        if (_musicActive) unawaited(_musicPlayer?.pause());
        _showPlayIcon = true;
      } else {
        c.play();
        if (_musicActive) unawaited(_musicPlayer?.resume());
        _showPlayIcon = false;
      }
    });

    if (_showPlayIcon) {
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) setState(() => _showPlayIcon = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return _VideoErrorPlaceholder(fillParent: widget.coverFullscreen);
    }

    final c = _controller;
    if (!_initialized || c == null || !c.value.isInitialized) {
      if (widget.coverFullscreen) {
        return const SizedBox.expand(
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

    final ratio = widget.aspectRatio ?? c.value.aspectRatio;

    return GestureDetector(
      onTap: () {
        _togglePlay();
        widget.onTap?.call();
      },
      child: widget.coverFullscreen
          ? _CoverFullscreenVideo(
              controller: c,
              showControls: widget.showControls,
              showPlayIcon: _showPlayIcon,
              isPlaying: c.value.isPlaying,
              onMuteTap: _toggleMute,
            )
          : AspectRatio(
              aspectRatio: ratio,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  VideoPlayer(c),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: VideoProgressIndicator(
                      c,
                      allowScrubbing: false,
                      colors: const VideoProgressColors(
                        playedColor: Colors.white,
                        bufferedColor: Colors.white30,
                        backgroundColor: Colors.transparent,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                  ),
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
                          c.value.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                    ),
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
                          _audioState.isMuted.value
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

class _CoverFullscreenVideo extends StatelessWidget {
  const _CoverFullscreenVideo({
    required this.controller,
    required this.showControls,
    required this.showPlayIcon,
    required this.isPlaying,
    required this.onMuteTap,
  });

  final VideoPlayerController controller;
  final bool showControls;
  final bool showPlayIcon;
  final bool isPlaying;
  final VoidCallback onMuteTap;

  @override
  Widget build(BuildContext context) {
    final sz = controller.value.size;
    final w = sz.width;
    final h = sz.height;

    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: w > 0 ? w : 1,
                  height: h > 0 ? h : 1,
                  child: VideoPlayer(controller),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: VideoProgressIndicator(
              controller,
              allowScrubbing: false,
              colors: const VideoProgressColors(
                playedColor: Colors.white,
                bufferedColor: Colors.white30,
                backgroundColor: Colors.transparent,
              ),
              padding: EdgeInsets.zero,
            ),
          ),
          if (showControls && showPlayIcon)
            AnimatedOpacity(
              opacity: showPlayIcon ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: const BoxDecoration(
                    color: Colors.black45,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
              ),
            ),
          // Внизу справа: под колонкой лайков/репостов, ближе к нижнему краю рилса.
          Positioned(
            right: 8,
            bottom: 10 + MediaQuery.paddingOf(context).bottom,
            child: ValueListenableBuilder<bool>(
              valueListenable: GlobalVideoAudioState.instance.isMuted,
              builder: (context, muted, _) {
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onMuteTap,
                    customBorder: const CircleBorder(),
                    child: Ink(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Icon(
                        muted
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoErrorPlaceholder extends StatelessWidget {
  const _VideoErrorPlaceholder({this.fillParent = false});

  final bool fillParent;

  @override
  Widget build(BuildContext context) {
    const message = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.videocam_off_rounded, color: Colors.white38, size: 40),
        SizedBox(height: 8),
        Text(
          'Не удалось загрузить видео',
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
      ],
    );

    if (fillParent) {
      return const SizedBox.expand(
        child: ColoredBox(
          color: Color(0xFF1A1A1A),
          child: Center(child: message),
        ),
      );
    }

    return const AspectRatio(
      aspectRatio: 9 / 16,
      child: ColoredBox(
        color: Color(0xFF1A1A1A),
        child: Center(child: message),
      ),
    );
  }
}
