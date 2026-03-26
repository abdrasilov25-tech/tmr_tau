import 'package:flutter/material.dart';

/// Оборачивает [child]; при двойном тапе вызывает [onDoubleTapLike] и показывает
/// краткую анимацию сердца (как в Instagram).
class DoubleTapLikeBurst extends StatefulWidget {
  const DoubleTapLikeBurst({
    super.key,
    required this.child,
    required this.onDoubleTapLike,
    this.canDoubleTap,
    this.shouldTriggerLike,
    this.showPersistentLikeIndicator = false,
    this.isLiked = false,
    this.iconSize = 92,
  });

  final Widget child;
  final VoidCallback onDoubleTapLike;

  /// Если задано и возвращает `false`, анимация и [onDoubleTapLike] не выполняются
  /// (например, показали подсказку «Войдите»).
  final bool Function()? canDoubleTap;

  /// Если задано и возвращает `false`, двойной тап не вызывает лайк.
  /// Полезно для поведения "double tap только ставит лайк".
  final bool Function()? shouldTriggerLike;
  final bool showPersistentLikeIndicator;
  final bool isLiked;
  final double iconSize;

  @override
  State<DoubleTapLikeBurst> createState() => _DoubleTapLikeBurstState();
}

class _DoubleTapLikeBurstState extends State<DoubleTapLikeBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.5, end: 1.15).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.15, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: ConstantTween(1.0),
        weight: 40,
      ),
    ]).animate(_controller);

    _opacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeOut)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: ConstantTween(1.0),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)),
        weight: 35,
      ),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    if (widget.canDoubleTap != null && !widget.canDoubleTap!()) {
      return;
    }
    final shouldTriggerLike = widget.shouldTriggerLike == null || widget.shouldTriggerLike!();
    if (shouldTriggerLike) {
      widget.onDoubleTapLike();
    }
    _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onDoubleTap: _handleDoubleTap,
          behavior: HitTestBehavior.translucent,
          child: widget.child,
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                if (_controller.value == 0) {
                  if (!widget.showPersistentLikeIndicator || !widget.isLiked) {
                    return const SizedBox.shrink();
                  }
                  return Align(
                    alignment: Alignment.bottomRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 14, bottom: 14),
                      child: Icon(
                        Icons.favorite,
                        size: 22,
                        color: Colors.redAccent.withValues(alpha: 0.95),
                        shadows: const [
                          Shadow(blurRadius: 8, color: Colors.black45),
                        ],
                      ),
                    ),
                  );
                }
                return Center(
                  child: Opacity(
                    opacity: _opacity.value.clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: _scale.value,
                      child: Icon(
                        Icons.favorite,
                        size: widget.iconSize,
                        color: Colors.white,
                        shadows: const [
                          Shadow(blurRadius: 12, color: Colors.black45),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
