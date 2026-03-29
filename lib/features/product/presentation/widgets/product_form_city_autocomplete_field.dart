import 'package:flutter/material.dart';

import '../../../../core/data/kazakhstan_regions.dart';

/// Город с подсказками из справочника РК (без лишнего setState у родителя).
class ProductFormCityAutocompleteField extends StatelessWidget {
  const ProductFormCityAutocompleteField({
    super.key,
    required this.controller,
    required this.focusNode,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: controller,
      focusNode: focusNode,
      displayStringForOption: (o) => o,
      optionsBuilder: (value) {
        if (value.text.trim().length < 2) {
          return const Iterable<String>.empty();
        }
        return KazakhstanRegions.suggestCities(value.text);
      },
      onSelected: (s) {
        controller.text = s;
        controller.selection = TextSelection.collapsed(offset: s.length);
      },
      fieldViewBuilder: (context, fieldController, fieldFocus, onFieldSubmitted) {
        return TextFormField(
          controller: fieldController,
          focusNode: fieldFocus,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Город *',
            hintText: 'Начните ввод — подсказки по городам РК',
          ),
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Укажите город' : null,
          onFieldSubmitted: (_) => onFieldSubmitted(),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final list = options.toList(growable: false);
        if (list.isEmpty) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final o = list[i];
                  return ListTile(
                    dense: true,
                    title: Text(o),
                    onTap: () => onSelected(o),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
