import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Полоса загрузки: трамвай (PNG) едет слева направо с лёгкой болтанкой и дымом сверху.
class TemirtauTramLoader extends StatefulWidget {
  const TemirtauTramLoader({
    super.key,
    this.height = 100,
    this.duration = const Duration(milliseconds: 4500),
    this.assetPath = 'assets/splash_tram_photo.png',
  });

  final double height;
  final Duration duration;
  final String assetPath;

  @override
  State<TemirtauTramLoader> createState() => _TemirtauTramLoaderState();
}

class _TemirtauTramLoaderState extends State<TemirtauTramLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _drive;

  @override
  void initState() {
    super.initState();
    _drive = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
  }

  @override
  void dispose() {
    _drive.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tramH = widget.height * 0.78;
    // Боковой ракурс — шире, чем у старого ассета.
    final tramW = tramH * 2.78;
    // Место над полосой, чтобы дым не резался ClipRRect.
    final topPad = (tramH * 0.16).clamp(6.0, 14.0);
    final innerH = widget.height + topPad;

    return SizedBox(
      height: innerH,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final trackW = constraints.maxWidth;
          final radius = (widget.height * 0.38).clamp(14.0, 22.0);
          final railY = innerH - widget.height * 0.26;
          return ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: AnimatedBuilder(
              animation: _drive,
              builder: (context, child) {
                final raw = _drive.value;
                // Плавный разгон и замедление в конце цикла (как у электротранспорта).
                final tMove = Curves.easeInOutCubic.transform(raw);
                final x = -tramW + tMove * (trackW + tramW * 1.02);
                // Лёгкая «болтанка» от рельсов.
                final bob =
                    math.sin(raw * math.pi * 2 * 2.4) * (widget.height * 0.028).clamp(0.4, 3.0);
                final sway = math.sin(raw * math.pi * 2 * 1.7) * 0.011;

                return Stack(
                  clipBehavior: Clip.hardEdge,
                  alignment: Alignment.centerLeft,
                  children: [
                    CustomPaint(
                      size: Size(trackW, innerH),
                      painter: _DarkTrackPainter(
                        width: trackW,
                        height: innerH,
                        radius: radius,
                        phase: raw,
                        railY: railY,
                      ),
                    ),
                    Positioned(
                      left: x,
                      top: topPad + (widget.height - tramH) / 2 + bob,
                      child: RepaintBoundary(
                        child: Transform.rotate(
                          angle: sway,
                          alignment: Alignment.bottomCenter,
                          child: SizedBox(
                            width: tramW,
                            height: tramH,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Positioned.fill(
                                  child: Image.asset(
                                    widget.assetPath,
                                    fit: BoxFit.contain,
                                    alignment: Alignment.center,
                                    filterQuality: FilterQuality.medium,
                                    isAntiAlias: true,
                                    errorBuilder: (context, error, stackTrace) =>
                                        Icon(
                                      Icons.tram_rounded,
                                      size: tramH * 0.6,
                                      color: Colors.white38,
                                    ),
                                  ),
                                ),
                                // Дым над крышей (зона пантографа / вентиляции).
                                Positioned(
                                  left: tramW * 0.30,
                                  right: tramW * 0.34,
                                  top: -tramH * 0.20,
                                  height: tramH * 0.48,
                                  child: CustomPaint(
                                    size: Size(tramW * 0.36, tramH * 0.48),
                                    painter: _TramSmokePainter(phase: raw),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// Мягкие клубы дыма, уносящиеся назад и вверх.
class _TramSmokePainter extends CustomPainter {
  _TramSmokePainter({required this.phase});

  final double phase;

  static double _hash(int i, double t) {
    final x = (math.sin(i * 12.9898 + t * 78.233) * 43758.5453).abs();
    return (x - x.floorToDouble()).clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final emitX = w * 0.52;
    final emitY = h * 0.88;

    const layers = 2;
    const perLayer = 14;

    for (var layer = 0; layer < layers; layer++) {
      final layerShift = layer * 0.37;
      for (var i = 0; i < perLayer; i++) {
        final stagger = (i + layer * perLayer * 0.5) / (perLayer * layers);
        var p = (phase * (layer == 0 ? 1.65 : 2.1) + stagger + layerShift) % 1.0;
        // Ветер назад относительно движения вправо.
        final windBack = -p * w * 0.22;
        final wobble =
            math.sin(p * math.pi * 5 + i * 0.9 + layer) * w * 0.07;
        final cx = emitX + windBack + wobble;
        final cy = emitY - p * h * 1.05 - layer * 2.0;
        final hVar = _hash(i, phase);
        final r = (2.2 + p * 10.5 + layer * 1.5) * (0.65 + 0.35 * hVar);
        final a = (((1.0 - p) * 0.38) * (layer == 0 ? 1.0 : 0.55)).clamp(0.0, 0.4);

        final paint = Paint()
          ..color = Color.fromRGBO(
            235 - layer * 8,
            238 - layer * 6,
            242 - layer * 4,
            a,
          )
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1.2 + p * 2.0);

        canvas.drawCircle(Offset(cx, cy), r, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TramSmokePainter oldDelegate) =>
      oldDelegate.phase != phase;
}

class _DarkTrackPainter extends CustomPainter {
  _DarkTrackPainter({
    required this.width,
    required this.height,
    required this.radius,
    required this.phase,
    required this.railY,
  });

  final double width;
  final double height;
  final double radius;
  final double phase;
  final double railY;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, width, height),
      Radius.circular(radius),
    );

    final bg = Paint()
      ..shader = ui.Gradient.linear(
        Offset(phase * 28, 0),
        Offset(width + phase * 28, height),
        [
          const Color(0xFF151922),
          const Color(0xFF1C222E),
          const Color(0xFF151922),
        ],
        const [0.0, 0.5, 1.0],
      );
    canvas.drawRRect(r, bg);

    final innerSheen = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, 0),
        Offset(0, height),
        [
          Colors.white.withValues(alpha: 0.04),
          Colors.transparent,
          Colors.black.withValues(alpha: 0.12),
        ],
        const [0.0, 0.45, 1.0],
      );
    canvas.drawRRect(r, innerSheen);

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.09);
    canvas.drawRRect(r, border);

    final rail = Paint()
      ..color = Colors.white.withValues(alpha: 0.14)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final y = railY.clamp(8.0, height - 8.0);
    canvas.drawLine(Offset(14, y), Offset(width - 14, y), rail);

    final dashPaint = Paint()
      ..color = const Color(0xFF8D6E63).withValues(alpha: 0.45)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    const dash = 6.0;
    const gap = 5.0;
    var x = (phase * 24) % (dash + gap);
    while (x < width - 12) {
      canvas.drawLine(Offset(12 + x, y), Offset(12 + x + dash, y), dashPaint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DarkTrackPainter oldDelegate) =>
      oldDelegate.width != width ||
      oldDelegate.height != height ||
      oldDelegate.radius != radius ||
      oldDelegate.phase != phase ||
      oldDelegate.railY != railY;
}
