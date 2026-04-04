import 'dart:async';

import 'package:flutter/material.dart';

/// Постепенная «печать» строки с градиентом и мигающим курсором.
class TypewriterBrandText extends StatefulWidget {
  const TypewriterBrandText({
    super.key,
    required this.text,
    this.perCharacter = const Duration(milliseconds: 72),
  });

  final String text;
  final Duration perCharacter;

  @override
  State<TypewriterBrandText> createState() => _TypewriterBrandTextState();
}

class _TypewriterBrandTextState extends State<TypewriterBrandText>
    with SingleTickerProviderStateMixin {
  int _visibleCount = 0;
  Timer? _timer;
  late AnimationController _cursorBlink;

  @override
  void initState() {
    super.initState();
    _cursorBlink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 530),
    )..repeat(reverse: true);

    _timer = Timer.periodic(widget.perCharacter, (_) {
      if (!mounted) return;
      if (_visibleCount < widget.text.length) {
        setState(() => _visibleCount++);
      } else {
        _timer?.cancel();
        _timer = null;
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cursorBlink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = widget.text.substring(0, _visibleCount);
    final done = _visibleCount >= widget.text.length;

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) {
              return const LinearGradient(
                colors: [
                  Color(0xFFFFF8E1),
                  Color(0xFFFFD54F),
                  Colors.white,
                  Color(0xFF90CAF9),
                ],
                stops: [0.0, 0.35, 0.55, 1.0],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ).createShader(bounds);
            },
            child: Text(
              shown,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                height: 1.1,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.45,
                color: Colors.white,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.9),
                    blurRadius: 14,
                    offset: const Offset(0, 2),
                  ),
                  Shadow(
                    color: const Color(0xFFFFD54F).withValues(alpha: 0.5),
                    blurRadius: 20,
                  ),
                ],
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _cursorBlink,
            builder: (context, child) {
              final showCursor = !done || _cursorBlink.value > 0.35;
              if (!showCursor) return const SizedBox(width: 0, height: 20);
              return Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 2),
                child: Opacity(
                  opacity: done ? _cursorBlink.value : 1.0,
                  child: Container(
                    width: 3,
                    height: 18,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFDE7),
                      borderRadius: BorderRadius.circular(1),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFFD54F).withValues(alpha: 0.85),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
