import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Полоса загрузки: реальный трамвай (фото) едет слева направо на тёмном фоне.
class TemirtauTramLoader extends StatefulWidget {
  const TemirtauTramLoader({
    super.key,
    this.height = 100,
    this.duration = const Duration(milliseconds: 3800),
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
    final tramW = tramH * 2.4;

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final trackW = constraints.maxWidth;
          final radius = (widget.height * 0.38).clamp(14.0, 22.0);
          return ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: AnimatedBuilder(
              animation: _drive,
              builder: (context, child) {
                final t = Curves.easeInOut.transform(_drive.value);
                final x = -tramW + t * (trackW + tramW * 1.02);
                return Stack(
                  clipBehavior: Clip.hardEdge,
                  alignment: Alignment.centerLeft,
                  children: [
                    CustomPaint(
                      size: Size(trackW, widget.height),
                      painter: _DarkTrackPainter(
                        width: trackW,
                        height: widget.height,
                        radius: radius,
                        phase: _drive.value,
                      ),
                    ),
                    Positioned(
                      left: x,
                      top: (widget.height - tramH) / 2,
                      child: RepaintBoundary(
                        child: SizedBox(
                          width: tramW,
                          height: tramH,
                          child: Image.asset(
                            widget.assetPath,
                            fit: BoxFit.contain,
                            alignment: Alignment.center,
                            filterQuality: FilterQuality.medium,
                            isAntiAlias: true,
                            errorBuilder: (context, error, stackTrace) => Icon(
                              Icons.tram_rounded,
                              size: tramH * 0.6,
                              color: Colors.white38,
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

class _DarkTrackPainter extends CustomPainter {
  _DarkTrackPainter({
    required this.width,
    required this.height,
    required this.radius,
    required this.phase,
  });

  final double width;
  final double height;
  final double radius;
  final double phase;

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
    final y = height * 0.72;
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
      oldDelegate.phase != phase;
}
