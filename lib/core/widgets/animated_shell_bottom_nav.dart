import 'package:flutter/material.dart';

const double _kShellNavHitHeight = 52;

/// Спецификация вкладки нижней навигации основного shell.
class ShellNavTabSpec {
  const ShellNavTabSpec({
    required this.semanticsLabel,
    required this.iconOutlined,
    required this.iconFilled,
    required this.gradient,
    this.badgeLabel = '',
  });

  final String semanticsLabel;
  final IconData iconOutlined;
  final IconData iconFilled;
  /// Акцент вкладки (пилюля и оттенок иконки в покое).
  final List<Color> gradient;
  final String badgeLabel;
}

/// Нижняя навигация: плавная пилюля-индикатор и цветные иконки.
class AnimatedShellBottomNav extends StatelessWidget {
  const AnimatedShellBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.items,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<ShellNavTabSpec> items;

  static const double _barHeight = 60;
  static const Duration _pillDuration = Duration(milliseconds: 380);
  static const Curve _pillCurve = Curves.easeOutCubic;

  @override
  Widget build(BuildContext context) {
    assert(items.isNotEmpty, 'items');
    final safeIndex = selectedIndex.clamp(0, items.length - 1);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 18,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: _barHeight,
          child: LayoutBuilder(
            builder: (context, c) {
              final n = items.length;
              final w = c.maxWidth / n;
              final pillW = w * 0.72;
              final pillLeft = safeIndex * w + (w - pillW) / 2;
              final grad = items[safeIndex].gradient;
              return Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedPositioned(
                    duration: _pillDuration,
                    curve: _pillCurve,
                    left: pillLeft,
                    top: 10,
                    width: pillW,
                    height: 40,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: grad.length >= 2
                              ? grad
                              : [grad.first, grad.first.withValues(alpha: 0.75)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: grad.first.withValues(alpha: 0.42),
                            blurRadius: 14,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    children: List.generate(n, (i) {
                      final spec = items[i];
                      final selected = i == safeIndex;
                      return Expanded(
                        child: _ShellNavTap(
                          semanticsLabel: spec.semanticsLabel,
                          selected: selected,
                          accent: spec.gradient.first,
                          icon: selected ? spec.iconFilled : spec.iconOutlined,
                          badgeLabel: spec.badgeLabel,
                          onTap: () => onDestinationSelected(i),
                        ),
                      );
                    }),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ShellNavTap extends StatelessWidget {
  const _ShellNavTap({
    required this.semanticsLabel,
    required this.selected,
    required this.accent,
    required this.icon,
    required this.badgeLabel,
    required this.onTap,
  });

  final String semanticsLabel;
  final bool selected;
  final Color accent;
  final IconData icon;
  final String badgeLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final showBadge = badgeLabel.isNotEmpty;
    final iconWidget = AnimatedScale(
      scale: selected ? 1.1 : 1,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      child: Icon(
        icon,
        size: 26,
        color: selected ? Colors.white : accent.withValues(alpha: 0.58),
      ),
    );

    final child = Badge(
      isLabelVisible: showBadge,
      backgroundColor: const Color(0xFF2563EB),
      textColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      label: Text(
        badgeLabel,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      child: iconWidget,
    );

    return Semantics(
      label: semanticsLabel,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          splashColor: accent.withValues(alpha: 0.12),
          highlightColor: accent.withValues(alpha: 0.08),
          child: SizedBox(
            height: _kShellNavHitHeight,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
