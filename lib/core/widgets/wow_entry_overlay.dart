import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../feedback/feedback_manager.dart';

enum WowEntryType { battle, shop, wallet }

/// One-shot "wow" entry animation overlay.
///
/// Wraps [child] in a Stack and plays a themed full-screen animation
/// for ~1.4 s on first mount, then disappears.
///
/// Usage:
/// ```dart
/// WowEntryOverlay(type: WowEntryType.battle, child: MyPage())
/// ```
class WowEntryOverlay extends StatefulWidget {
  const WowEntryOverlay({
    super.key,
    required this.child,
    required this.type,
  });

  final Widget child;
  final WowEntryType type;

  @override
  State<WowEntryOverlay> createState() => _WowEntryOverlayState();
}

class _WowEntryOverlayState extends State<WowEntryOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _triggerSound();
      _ctrl.forward().then((_) {
        if (mounted) setState(() => _done = true);
      });
    });
  }

  void _triggerSound() {
    try {
      switch (widget.type) {
        case WowEntryType.battle:
          FeedbackManager.instance.battleEntry();
        case WowEntryType.shop:
          FeedbackManager.instance.shopEntry();
        case WowEntryType.wallet:
          FeedbackManager.instance.walletEntry();
      }
    } catch (e) { debugPrint('$e'); }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        switch (widget.type) {
          WowEntryType.battle => _BattleOverlay(ctrl: _ctrl),
          WowEntryType.shop => _ShopOverlay(ctrl: _ctrl),
          WowEntryType.wallet => _WalletOverlay(ctrl: _ctrl),
        },
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BATTLE — dark flash, two swords colliding, sparks + "BATTLE" text
// ─────────────────────────────────────────────────────────────────────────────

class _BattleOverlay extends StatelessWidget {
  const _BattleOverlay({required this.ctrl});
  final AnimationController ctrl;

  @override
  Widget build(BuildContext context) {
    // Overall fade: in 0→0.15, hold 0.15→0.8, out 0.8→1.0
    final fadeIn = CurvedAnimation(
      parent: ctrl,
      curve: const Interval(0.0, 0.15, curve: Curves.easeIn),
    );
    final fadeOut = CurvedAnimation(
      parent: ctrl,
      curve: const Interval(0.80, 1.0, curve: Curves.easeOut),
    );

    // Swords slide in: 0.1→0.45
    final swordIn = CurvedAnimation(
      parent: ctrl,
      curve: const Interval(0.10, 0.45, curve: Curves.easeOutBack),
    );
    // Text pop: 0.4→0.65
    final textPop = CurvedAnimation(
      parent: ctrl,
      curve: const Interval(0.40, 0.65, curve: Curves.elasticOut),
    );

    return Positioned.fill(
      child: AnimatedBuilder(
        animation: ctrl,
        builder: (ctx, _) {
          final opacity = fadeIn.value * (1.0 - fadeOut.value);
          return Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Background gradient
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xDD0A0014), Color(0xDD1A0030), Color(0xDD0A0014)],
                    ),
                  ),
                ),

                // Spark particles
                CustomPaint(
                  painter: _BattleSparksPainter(progress: ctrl.value),
                ),

                // Left sword sliding in from left
                Align(
                  alignment: Alignment.centerLeft,
                  child: Transform.translate(
                    offset: Offset(-200 * (1 - swordIn.value), 0),
                    child: const Padding(
                      padding: EdgeInsets.only(left: 40),
                      child: _SwordIcon(flip: false),
                    ),
                  ),
                ),

                // Right sword sliding in from right (flipped)
                Align(
                  alignment: Alignment.centerRight,
                  child: Transform.translate(
                    offset: Offset(200 * (1 - swordIn.value), 0),
                    child: const Padding(
                      padding: EdgeInsets.only(right: 40),
                      child: _SwordIcon(flip: true),
                    ),
                  ),
                ),

                // "⚔ BATTLE" center text
                Center(
                  child: Transform.scale(
                    scale: textPop.value.clamp(0.0, 1.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('⚔', style: TextStyle(fontSize: 56)),
                        const SizedBox(height: 8),
                        Text(
                          'BATTLE',
                          style: TextStyle(
                            fontSize: 38,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 8,
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                color: const Color(0xFFAB6FFF),
                                blurRadius: 24,
                              ),
                              Shadow(
                                color: Colors.purpleAccent,
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SwordIcon extends StatelessWidget {
  const _SwordIcon({required this.flip});
  final bool flip;

  @override
  Widget build(BuildContext context) {
    return Transform.flip(
      flipX: flip,
      child: const Text('🗡️', style: TextStyle(fontSize: 52)),
    );
  }
}

class _BattleSparksPainter extends CustomPainter {
  _BattleSparksPainter({required this.progress});
  final double progress;

  // Pre-seeded sparks: [angle, speed, size]
  static final List<List<double>> _sparks = List.generate(28, (i) {
    final rng = math.Random(i * 37 + 7);
    return [
      rng.nextDouble() * 2 * math.pi,
      rng.nextDouble() * 160 + 60,
      rng.nextDouble() * 3 + 1.5,
    ];
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress < 0.35 || progress > 0.85) return;
    final t = ((progress - 0.35) / 0.50).clamp(0.0, 1.0);
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..style = PaintingStyle.fill;

    for (final spark in _sparks) {
      final angle = spark[0];
      final dist = spark[1] * t;
      final r = spark[2];
      final alpha = (1.0 - t * t).clamp(0.0, 1.0);
      final pos = center + Offset(math.cos(angle) * dist, math.sin(angle) * dist);
      final colors = [Colors.purpleAccent, Colors.white, Colors.yellowAccent, const Color(0xFFFF6B6B)];
      paint.color = colors[(_sparks.indexOf(spark)) % colors.length].withValues(alpha: alpha);
      canvas.drawCircle(pos, r, paint);
    }
  }

  @override
  bool shouldRepaint(_BattleSparksPainter old) => old.progress != progress;
}

// ─────────────────────────────────────────────────────────────────────────────
// SHOP — rainbow confetti burst + sparkle stars + "✨ SHOP" text
// ─────────────────────────────────────────────────────────────────────────────

class _ShopOverlay extends StatelessWidget {
  const _ShopOverlay({required this.ctrl});
  final AnimationController ctrl;

  @override
  Widget build(BuildContext context) {
    final fadeIn = CurvedAnimation(
      parent: ctrl,
      curve: const Interval(0.0, 0.12, curve: Curves.easeIn),
    );
    final fadeOut = CurvedAnimation(
      parent: ctrl,
      curve: const Interval(0.78, 1.0, curve: Curves.easeOut),
    );
    final textPop = CurvedAnimation(
      parent: ctrl,
      curve: const Interval(0.30, 0.58, curve: Curves.elasticOut),
    );

    return Positioned.fill(
      child: AnimatedBuilder(
        animation: ctrl,
        builder: (ctx, _) {
          final opacity = fadeIn.value * (1.0 - fadeOut.value);
          return Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Soft gradient background
                Container(
                  decoration: const BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.center,
                      radius: 1.2,
                      colors: [Color(0xCC8B5CF6), Color(0xCCEC4899), Color(0xCC0F0F1A)],
                    ),
                  ),
                ),

                // Confetti
                CustomPaint(
                  painter: _ConfettiPainter(progress: ctrl.value),
                ),

                // Stars floating up
                CustomPaint(
                  painter: _StarsPainter(progress: ctrl.value),
                ),

                // "✨" + text center
                Center(
                  child: Transform.scale(
                    scale: textPop.value.clamp(0.0, 1.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('✨', style: TextStyle(fontSize: 60)),
                        const SizedBox(height: 6),
                        Text(
                          'МАГАЗИН',
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 5,
                            color: Colors.white,
                            shadows: [
                              Shadow(color: const Color(0xFFEC4899), blurRadius: 20),
                              Shadow(color: Colors.white, blurRadius: 4),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'питомцев',
                          style: TextStyle(
                            fontSize: 16,
                            letterSpacing: 3,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.progress});
  final double progress;

  static final List<_ConfettiPiece> _pieces = List.generate(50, (i) {
    final rng = math.Random(i * 53 + 11);
    return _ConfettiPiece(
      angle: rng.nextDouble() * 2 * math.pi,
      speed: rng.nextDouble() * 220 + 80,
      rotSpeed: rng.nextDouble() * 6 - 3,
      size: rng.nextDouble() * 7 + 4,
      color: _confettiColors[i % _confettiColors.length],
      startPhase: rng.nextDouble() * 0.15,
      isRect: i % 3 != 0,
    );
  });

  static const _confettiColors = [
    Color(0xFFEC4899), Color(0xFF8B5CF6), Color(0xFF06B6D4),
    Color(0xFFF59E0B), Color(0xFF10B981), Color(0xFFF97316),
    Color(0xFFEF4444), Color(0xFFFFFFFF),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..style = PaintingStyle.fill;

    for (final p in _pieces) {
      if (progress < p.startPhase) continue;
      final t = ((progress - p.startPhase) / (1.0 - p.startPhase)).clamp(0.0, 1.0);
      final dist = p.speed * t;
      // Gravity effect
      final gravity = 80.0 * t * t;
      final pos = center +
          Offset(math.cos(p.angle) * dist, math.sin(p.angle) * dist + gravity);
      final alpha = (1.0 - math.pow(t, 2.5)).clamp(0.0, 1.0).toDouble();
      paint.color = p.color.withValues(alpha: alpha);

      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(p.rotSpeed * t * math.pi);
      if (p.isRect) {
        canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.5),
          paint,
        );
      } else {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.progress != progress;
}

class _ConfettiPiece {
  const _ConfettiPiece({
    required this.angle,
    required this.speed,
    required this.rotSpeed,
    required this.size,
    required this.color,
    required this.startPhase,
    required this.isRect,
  });
  final double angle;
  final double speed;
  final double rotSpeed;
  final double size;
  final Color color;
  final double startPhase;
  final bool isRect;
}

class _StarsPainter extends CustomPainter {
  _StarsPainter({required this.progress});
  final double progress;

  static final List<(double x, double speed, double size)> _stars =
      List.generate(14, (i) {
    final rng = math.Random(i * 17 + 3);
    return (rng.nextDouble(), rng.nextDouble() * 120 + 60, rng.nextDouble() * 10 + 6);
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress < 0.1) return;
    final t = ((progress - 0.1) / 0.8).clamp(0.0, 1.0);
    final paint = Paint()..style = PaintingStyle.fill;

    for (final (xFrac, speed, sz) in _stars) {
      final x = xFrac * size.width;
      final y = size.height * 0.7 - speed * t;
      final alpha = (math.sin(t * math.pi)).clamp(0.0, 1.0);
      paint.color = Colors.yellowAccent.withValues(alpha: alpha * 0.9);
      // Draw a 4-pointed star
      final r1 = sz;
      final r2 = sz * 0.4;
      final path = Path();
      for (int k = 0; k < 8; k++) {
        final a = k * math.pi / 4 - math.pi / 8;
        final r = k.isEven ? r1 : r2;
        final p = Offset(x + math.cos(a) * r, y + math.sin(a) * r);
        if (k == 0) { path.moveTo(p.dx, p.dy); } else { path.lineTo(p.dx, p.dy); }
      }
      path.close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_StarsPainter old) => old.progress != progress;
}

// ─────────────────────────────────────────────────────────────────────────────
// WALLET — gold shimmer sweep + raining coins + "💰 QARMET" text
// ─────────────────────────────────────────────────────────────────────────────

class _WalletOverlay extends StatelessWidget {
  const _WalletOverlay({required this.ctrl});
  final AnimationController ctrl;

  @override
  Widget build(BuildContext context) {
    final fadeIn = CurvedAnimation(
      parent: ctrl,
      curve: const Interval(0.0, 0.14, curve: Curves.easeIn),
    );
    final fadeOut = CurvedAnimation(
      parent: ctrl,
      curve: const Interval(0.78, 1.0, curve: Curves.easeOut),
    );
    final shimmerSlide = CurvedAnimation(
      parent: ctrl,
      curve: const Interval(0.0, 0.55, curve: Curves.easeInOut),
    );
    final textPop = CurvedAnimation(
      parent: ctrl,
      curve: const Interval(0.35, 0.62, curve: Curves.elasticOut),
    );

    return Positioned.fill(
      child: AnimatedBuilder(
        animation: ctrl,
        builder: (ctx, _) {
          final opacity = fadeIn.value * (1.0 - fadeOut.value);
          return Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Dark gold gradient background
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xCC0F0A00),
                        Color(0xCC1C1200),
                        Color(0xCC0F0A00),
                      ],
                    ),
                  ),
                ),

                // Gold shimmer sweep
                ClipRect(
                  child: Align(
                    alignment: Alignment(shimmerSlide.value * 3 - 1.5, 0),
                    child: Container(
                      width: 120,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            const Color(0xFFFBBF24).withValues(alpha: 0.35),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Raining coins
                CustomPaint(
                  painter: _CoinRainPainter(progress: ctrl.value),
                ),

                // Center "💰 QARMET" text
                Center(
                  child: Transform.scale(
                    scale: textPop.value.clamp(0.0, 1.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('💰', style: TextStyle(fontSize: 64)),
                        const SizedBox(height: 6),
                        Text(
                          'QARMET',
                          style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 6,
                            color: const Color(0xFFFBBF24),
                            shadows: [
                              Shadow(
                                color: const Color(0xFFD97706),
                                blurRadius: 20,
                              ),
                              Shadow(
                                color: Colors.black,
                                blurRadius: 4,
                                offset: const Offset(1, 2),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'WALLET',
                          style: TextStyle(
                            fontSize: 14,
                            letterSpacing: 5,
                            color: const Color(0xFFFBBF24).withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CoinRainPainter extends CustomPainter {
  _CoinRainPainter({required this.progress});
  final double progress;

  static final List<(double xFrac, double delay, double speed, double size)> _coins =
      List.generate(18, (i) {
    final rng = math.Random(i * 29 + 5);
    return (
      rng.nextDouble(),
      rng.nextDouble() * 0.3,
      rng.nextDouble() * 250 + 180,
      rng.nextDouble() * 8 + 10,
    );
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (final (xFrac, delay, speed, sz) in _coins) {
      if (progress < delay) continue;
      final t = ((progress - delay) / (1.0 - delay)).clamp(0.0, 1.0);
      final x = xFrac * size.width;
      final y = -sz + speed * t;
      final alpha = (1.0 - math.max(0.0, t - 0.6) / 0.4).clamp(0.0, 1.0);

      if (y > size.height + sz) continue;

      // Gold coin body
      paint.color = const Color(0xFFFBBF24).withValues(alpha: alpha);
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, y), width: sz, height: sz * 0.72),
        paint,
      );
      // Dark ring
      strokePaint.color = const Color(0xFFD97706).withValues(alpha: alpha);
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, y), width: sz * 0.82, height: sz * 0.58),
        strokePaint,
      );
    }
  }

  @override
  bool shouldRepaint(_CoinRainPainter old) => old.progress != progress;
}
