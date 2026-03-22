import 'package:flutter/material.dart';

import '../../domain/entities/product_entity.dart';

/// **Визуализация:** бейджи «ТОП», «СРОЧНО», «ВЫДЕЛЕНО» на превью объявления.
/// Логика «показывать или нет» — в геттерах [ProductEntity.showTopBadge] и т.д.
class ProductPromoBadges extends StatelessWidget {
  const ProductPromoBadges({
    super.key,
    required this.product,
    this.compact = true,
  });

  final ProductEntity product;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      if (product.showTopBadge)
        _Badge(
          label: 'ТОП',
          color: const Color(0xFFFFC107),
          compact: compact,
        ),
      if (product.showUrgentBadge)
        _Badge(
          label: 'СРОЧНО',
          color: const Color(0xFFE53935),
          compact: compact,
        ),
      if (product.showHighlightBadge)
        _Badge(
          label: 'ВЫДЕЛЕНО',
          color: const Color(0xFF7C4DFF),
          compact: compact,
        ),
    ];
    if (children.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: children,
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.color,
    this.compact = true,
  });

  final String label;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.black87,
          fontWeight: FontWeight.w800,
          fontSize: compact ? 11 : 12,
        ),
      ),
    );
  }
}
