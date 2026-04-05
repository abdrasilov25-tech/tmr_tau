import 'dart:async';

import 'package:flutter/material.dart';

/// Нижняя зона превью сторис: мягкий градиент, тап и свайп вверх открывают лист стикеров.
///
/// Жест учитывает преимущественно вертикальное движение, чтобы не конфликтовать
/// с горизонтальными драгами (например, стикер музыки выше по стеку).
class StoryPreviewTrayHint extends StatefulWidget {
  const StoryPreviewTrayHint({
    super.key,
    required this.enabled,
    required this.loading,
    required this.height,
    required this.onOpen,
  });

  final bool enabled;
  final bool loading;
  final double height;
  final Future<void> Function() onOpen;

  @override
  State<StoryPreviewTrayHint> createState() => _StoryPreviewTrayHintState();
}

class _StoryPreviewTrayHintState extends State<StoryPreviewTrayHint> {
  double _vertAccum = 0;

  void _invokeOpen() {
    if (!widget.enabled || widget.loading) return;
    unawaited(widget.onOpen());
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: widget.height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.loading ? null : _invokeOpen,
        onVerticalDragStart: (_) => _vertAccum = 0,
        onVerticalDragUpdate: (details) {
          final dy = details.delta.dy;
          final dx = details.delta.dx;
          if (dy.abs() >= dx.abs() * 0.65) {
            _vertAccum += dy;
          }
        },
        onVerticalDragEnd: (details) {
          final v = details.primaryVelocity ?? 0;
          if (v < -190 || _vertAccum < -44) {
            _invokeOpen();
          }
          _vertAccum = 0;
        },
        onVerticalDragCancel: () => _vertAccum = 0,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.0),
                Colors.black.withValues(alpha: 0.38),
              ],
            ),
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.52),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        size: 18,
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Стикеры',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.96),
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.keyboard_arrow_up_rounded,
                        size: 24,
                        color: Colors.white.withValues(alpha: 0.62),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
