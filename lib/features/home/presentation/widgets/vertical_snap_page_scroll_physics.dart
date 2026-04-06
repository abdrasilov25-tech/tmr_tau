import 'package:flutter/material.dart';

/// Вертикальный page-view со «щёлком» между страницами (Reels / TikTok).
class VerticalSnapPageScrollPhysics extends ScrollPhysics {
  const VerticalSnapPageScrollPhysics({super.parent});

  @override
  VerticalSnapPageScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      VerticalSnapPageScrollPhysics(parent: buildParent(ancestor));

  @override
  SpringDescription get spring =>
      const SpringDescription(mass: 80, stiffness: 100, damping: 1);
}
