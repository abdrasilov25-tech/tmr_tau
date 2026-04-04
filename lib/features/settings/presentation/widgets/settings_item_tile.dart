import 'package:flutter/material.dart';

import '../../../../core/theme/themed_content_surface.dart';

/// Строка настроек: «поле» с иконкой в капсуле и скруглением (не голый ListTile).
class SettingsItemTile extends StatelessWidget {
  const SettingsItemTile({
    super.key,
    required this.title,
    required this.icon,
    this.customIcon,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.isDestructive = false,
    this.semanticLabel,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  /// Если задан — показывается вместо [icon] (Font Awesome и т.п.).
  final Widget? customIcon;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool isDestructive;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final destructive = isDestructive;
    final accent = destructive ? scheme.error : scheme.primary;
    final titleStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: destructive
              ? scheme.error
              : ThemedContentSurface.profileTextPrimary,
        );
    final subtitleStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: destructive
              ? scheme.error.withValues(alpha: 0.85)
              : scheme.onSurfaceVariant,
          height: 1.35,
        );

    return Semantics(
      button: onTap != null,
      label: semanticLabel ?? title,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: Material(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            splashColor: accent.withValues(alpha: 0.08),
            highlightColor: accent.withValues(alpha: 0.04),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: destructive
                          ? scheme.errorContainer.withValues(alpha: 0.55)
                          : scheme.primaryContainer.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: customIcon != null
                        ? Center(child: customIcon!)
                        : Icon(icon, color: accent, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title, style: titleStyle),
                        if (subtitle != null && subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: subtitleStyle,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  trailing ??
                      Icon(
                        Icons.chevron_right_rounded,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.65),
                        size: 26,
                      ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
