import 'package:flutter/material.dart';

/// Синяя галочка верификации (как в Instagram).
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.verified,
      size: size,
      color: const Color(0xFF3897F0),
    );
  }
}
