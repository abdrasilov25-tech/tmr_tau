import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Фон входа: арт Qarmet / Темиртау + мягкие «живые» блики (один тикер).
class SplashQarmetHeroBackdrop extends StatefulWidget {
  const SplashQarmetHeroBackdrop({
    super.key,
    this.assetPath = 'assets/splash_qarmet_hero.png',
  });

  final String assetPath;

  @override
  State<SplashQarmetHeroBackdrop> createState() =>
      _SplashQarmetHeroBackdropState();
}

class _SplashQarmetHeroBackdropState extends State<SplashQarmetHeroBackdrop>
    with SingleTickerProviderStateMixin {
  late AnimationController _ambient;

  @override
  void initState() {
    super.initState();
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
  }

  @override
  void dispose() {
    _ambient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        return ColoredBox(
          color: const Color(0xFF080A10),
          child: AnimatedBuilder(
            animation: _ambient,
            builder: (context, child) {
              final t = _ambient.value * math.pi * 2;
              // Лёгкое «дыхание» без уменьшения кадра — иначе по краям виден фон (как «обрезанная» картинка).
              final scale = 1.0 + 0.006 * math.sin(t * 0.85);
              return Stack(
                fit: StackFit.expand,
                children: [
                  Transform.scale(
                    scale: scale,
                    alignment: Alignment.center,
                    filterQuality: FilterQuality.low,
                    child: Image.asset(
                      widget.assetPath,
                      width: w,
                      height: h,
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (context, error, stackTrace) => const Center(
                        child: Icon(
                          Icons.image_not_supported_outlined,
                          color: Colors.white24,
                          size: 48,
                        ),
                      ),
                    ),
                  ),
                  // Лёгкое приглушение контраста по всему кадру
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFF12151C).withValues(alpha: 0.22),
                      ),
                    ),
                  ),
                  CustomPaint(
                    size: Size(w, h),
                    painter: _QarmetHeroFxPainter(phase: _ambient.value),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _QarmetHeroFxPainter extends CustomPainter {
  _QarmetHeroFxPainter({required this.phase});

  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final t = phase * math.pi * 2;

    // Золото слева — едва заметная тёплая дымка
    final goldA = 0.045 + 0.035 * (0.5 + 0.5 * math.sin(t * 0.95));
    final gold = Paint()
      ..blendMode = BlendMode.softLight
      ..shader = ui.Gradient.radial(
        Offset(w * 0.04, h * 0.4),
        w * 0.68,
        [
          const Color(0xFFFFE0B2).withValues(alpha: goldA),
          const Color(0xFFFFB74D).withValues(alpha: goldA * 0.4),
          Colors.transparent,
        ],
        const [0.0, 0.4, 1.0],
      );
    canvas.drawRect(Offset.zero & size, gold);

    // Справа — мягкий холодный оттенок без резкого screen
    final silverA = 0.028 + 0.028 * (0.5 + 0.5 * math.sin(t * 0.72 + 1.0));
    final silver = Paint()
      ..blendMode = BlendMode.softLight
      ..shader = ui.Gradient.radial(
        Offset(w * 0.96, h * 0.34),
        w * 0.58,
        [
          const Color(0xFFCFD8DC).withValues(alpha: silverA),
          const Color(0xFF78909C).withValues(alpha: silverA * 0.35),
          Colors.transparent,
        ],
        const [0.0, 0.42, 1.0],
      );
    canvas.drawRect(Offset.zero & size, silver);

    // Центр — очень слабый блик на медали
    final coinGlint =
        0.018 + 0.022 * (0.5 + 0.5 * math.sin(t * 1.1 + 0.5));
    final coin = Paint()
      ..blendMode = BlendMode.softLight
      ..shader = ui.Gradient.radial(
        Offset(w * 0.5, h * 0.46),
        w * 0.26,
        [
          Colors.white.withValues(alpha: coinGlint),
          Colors.white.withValues(alpha: coinGlint * 0.2),
          Colors.transparent,
        ],
        const [0.0, 0.5, 1.0],
      );
    canvas.drawRect(Offset.zero & size, coin);

    // Редкий мягкий блик (медленнее и слабее)
    final sweep = (phase * 1.35) % 1.0;
    final cx = w * (-0.3 + sweep * 1.55);
    final cy = h * 0.12;
    final shimmer = Paint()
      ..blendMode = BlendMode.softLight
      ..shader = ui.Gradient.linear(
        Offset(cx, cy),
        Offset(cx + w * 0.5, cy + h * 0.82),
        [
          Colors.transparent,
          Colors.white.withValues(alpha: 0.055),
          Colors.white.withValues(alpha: 0.08),
          Colors.white.withValues(alpha: 0.048),
          Colors.transparent,
        ],
        const [0.0, 0.4, 0.5, 0.6, 1.0],
      );
    canvas.drawRect(Offset.zero & size, shimmer);

    // Мягкая виньетка, почти без «пульса»
    final vigA = 0.26 + 0.035 * (0.5 + 0.5 * math.sin(t * 0.5));
    final vignette = Paint()
      ..shader = ui.Gradient.radial(
        Offset(w * 0.5, h * 0.5),
        w * 0.92,
        [
          Colors.transparent,
          const Color(0xFF0A0C10).withValues(alpha: vigA * 0.5),
          const Color(0xFF050608).withValues(alpha: vigA * 0.85),
        ],
        const [0.5, 0.82, 1.0],
      );
    canvas.drawRect(Offset.zero & size, vignette);

    // Лёгкое затемнение сверху и снизу — спокойнее для глаз
    final topShade = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        Offset(0, h * 0.18),
        [
          Colors.black.withValues(alpha: 0.22),
          Colors.transparent,
        ],
      );
    canvas.drawRect(Offset.zero & size, topShade);
    final bottomEase = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, h * 0.72),
        Offset(0, h),
        [
          Colors.transparent,
          Colors.black.withValues(alpha: 0.18),
        ],
      );
    canvas.drawRect(Offset.zero & size, bottomEase);
  }

  @override
  bool shouldRepaint(covariant _QarmetHeroFxPainter oldDelegate) =>
      oldDelegate.phase != phase;
}
