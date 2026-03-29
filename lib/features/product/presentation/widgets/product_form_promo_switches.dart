import 'package:flutter/material.dart';

import 'product_listing_promo_flags_controller.dart';

/// Срочно / ТОП / торг / даром — отдельный [ListenableBuilder] от цены.
class ProductFormPromoSwitches extends StatelessWidget {
  const ProductFormPromoSwitches({
    super.key,
    required this.flags,
  });

  final ProductListingPromoFlagsController flags;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: flags,
      builder: (context, _) {
        final giveaway = flags.isGiveaway;
        return Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Срочное объявление'),
              value: flags.isUrgent,
              onChanged: flags.setUrgent,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Поднять в ТОП'),
              value: flags.isTop,
              onChanged: flags.setTop,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Есть торг'),
              value: flags.isNegotiable,
              onChanged: giveaway ? null : flags.setNegotiable,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Отдам даром'),
              value: giveaway,
              onChanged: flags.setGiveaway,
            ),
          ],
        );
      },
    );
  }
}
