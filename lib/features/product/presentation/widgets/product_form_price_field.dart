import 'package:flutter/material.dart';

import 'product_listing_promo_flags_controller.dart';

/// Поле цены с учётом режима «Отдам даром» — локальный [ListenableBuilder].
class ProductFormPriceField extends StatelessWidget {
  const ProductFormPriceField({
    super.key,
    required this.flags,
    required this.priceController,
  });

  final ProductListingPromoFlagsController flags;
  final TextEditingController priceController;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: flags,
      builder: (context, _) {
        final giveaway = flags.isGiveaway;
        return TextFormField(
          controller: priceController,
          keyboardType: TextInputType.number,
          enabled: !giveaway,
          decoration: InputDecoration(
            labelText: giveaway ? 'Цена (даром)' : 'Цена (₸) *',
            hintText: '0',
            helperText: giveaway
                ? 'Для «Отдам даром» цена не указывается'
                : null,
          ),
          validator: (v) {
            if (giveaway) return null;
            if (v == null || v.trim().isEmpty) return 'Введите цену';
            final p = double.tryParse(
              v.replaceAll(' ', '').replaceAll(',', '.'),
            );
            if (p == null) return 'Некорректная цена';
            if (p <= 0) return 'Цена должна быть больше нуля';
            return null;
          },
        );
      },
    );
  }
}
