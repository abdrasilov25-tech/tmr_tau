import 'package:flutter/material.dart';

/// Иконки разделов городского чата (ключ из [CityChatThread.iconKey]).
IconData cityThreadMaterialIcon(String iconKey) {
  switch (iconKey) {
    case 'real_estate':
      return Icons.apartment_rounded;
    case 'services':
      return Icons.home_repair_service_rounded;
    case 'jobs':
      return Icons.work_outline_rounded;
    case 'purchases':
      return Icons.shopping_bag_outlined;
    case 'sales':
      return Icons.storefront_rounded;
    case 'dating':
      return Icons.favorite_rounded;
    case 'discussion':
      return Icons.forum_rounded;
    default:
      return Icons.tag_rounded;
  }
}

Color cityThreadAccentColor(String iconKey) {
  switch (iconKey) {
    case 'real_estate':
      return const Color(0xFF2563EB);
    case 'services':
      return const Color(0xFF7C3AED);
    case 'jobs':
      return const Color(0xFF059669);
    case 'purchases':
      return const Color(0xFFD97706);
    case 'sales':
      return const Color(0xFFDC2626);
    case 'dating':
      return const Color(0xFFDB2777);
    case 'discussion':
      return const Color(0xFF0891B2);
    default:
      return const Color(0xFF64748B);
  }
}
