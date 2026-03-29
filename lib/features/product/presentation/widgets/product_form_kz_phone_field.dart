import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/utils/kazakhstan_phone.dart';

/// Телефон РК: неизменяемый +7 и 10 цифр.
class ProductFormKzPhoneField extends StatelessWidget {
  const ProductFormKzPhoneField({
    super.key,
    required this.controller,
  });

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, right: 10),
          child: Text(
            '+7',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        Expanded(
          child: TextFormField(
            controller: controller,
            keyboardType: TextInputType.number,
            maxLength: 10,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
            ],
            decoration: const InputDecoration(
              labelText: 'Телефон для звонков *',
              hintText: '707 123 45 67',
              counterText: '',
              helperText:
                  '10 цифр после +7 (Казахстан). Покупатель увидит номер при «Позвонить»',
            ),
            validator: (v) {
              final ten = KazakhstanPhone.stripToTenDigits(v ?? '');
              if (ten.isEmpty) return 'Укажите номер';
              if (ten.length != 10) return 'Нужно 10 цифр после +7';
              return null;
            },
          ),
        ),
      ],
    );
  }
}
