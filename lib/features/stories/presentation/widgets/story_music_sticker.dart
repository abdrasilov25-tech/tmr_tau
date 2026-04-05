import 'package:flutter/material.dart';

/// Стикер «Музыка» в стиле Instagram: градиент, нота, название и исполнитель.
class StoryMusicSticker extends StatelessWidget {
  const StoryMusicSticker({
    super.key,
    required this.title,
    required this.artist,
    this.maxWidth = 280,
    this.hideTrackText = false,
  });

  final String title;
  final String artist;
  final double maxWidth;
  /// Как в Instagram: только иконка и волны, без названия и исполнителя.
  final bool hideTrackText;

  @override
  Widget build(BuildContext context) {
    if (hideTrackText) {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF7C4DFF).withValues(alpha: 0.95),
              const Color(0xFFE040FB).withValues(alpha: 0.92),
              const Color(0xFFFF4081).withValues(alpha: 0.9),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(
                Icons.music_note_rounded,
                color: Colors.white,
                size: 28,
              ),
              const SizedBox(width: 10),
              const _MiniWaveBars(),
            ],
          ),
        ),
      );
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF7C4DFF).withValues(alpha: 0.95),
              const Color(0xFFE040FB).withValues(alpha: 0.92),
              const Color(0xFFFF4081).withValues(alpha: 0.9),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(
                Icons.music_note_rounded,
                color: Colors.white,
                size: 28,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        height: 1.15,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (artist.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const _MiniWaveBars(),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniWaveBars extends StatelessWidget {
  const _MiniWaveBars();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _bar(10),
        const SizedBox(width: 3),
        _bar(18),
        const SizedBox(width: 3),
        _bar(14),
        const SizedBox(width: 3),
        _bar(22),
      ],
    );
  }

  Widget _bar(double h) {
    return Container(
      width: 3,
      height: h,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(1.5),
      ),
    );
  }
}

/// Подпись трека сверху кадра сторис (как в Instagram при выборе музыки).
class StoryMusicTopCaptionBar extends StatelessWidget {
  const StoryMusicTopCaptionBar({
    super.key,
    required this.title,
    required this.artist,
    this.hideTitles = false,
  });

  final String title;
  final String artist;
  /// Скрыть название и исполнителя (тап, как в Instagram).
  final bool hideTitles;

  static const List<Shadow> _shadows = [
    Shadow(
      color: Color(0xCC000000),
      blurRadius: 6,
      offset: Offset(0, 1),
    ),
    Shadow(
      color: Color(0x99000000),
      blurRadius: 12,
      offset: Offset(0, 2),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    if (hideTitles) {
      return const SizedBox.shrink();
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Нельзя: Row(mainAxisSize: min) + Flexible — ломает layout / assert во Flutter.
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.music_note_rounded,
              color: Colors.white.withValues(alpha: 0.95),
              size: 20,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  height: 1.2,
                  letterSpacing: -0.2,
                  shadows: _shadows,
                ),
              ),
            ),
          ],
        ),
        if (artist.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            artist.trim(),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.88),
              fontWeight: FontWeight.w600,
              fontSize: 13,
              shadows: _shadows,
            ),
          ),
        ],
      ],
    );
  }
}
