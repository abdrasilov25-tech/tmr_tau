import 'package:flutter/material.dart';

class ReportReasonPicker extends StatelessWidget {
  const ReportReasonPicker({
    super.key,
    required this.selectedReason,
    required this.onReasonChanged,
  });

  final String selectedReason;
  final ValueChanged<String> onReasonChanged;

  static const List<_Reason> _reasons = [
    _Reason('spam', 'Спам'),
    _Reason('abuse', 'Оскорбления'),
    _Reason('nudity', 'Ненормативный контент'),
    _Reason('copyright', 'Нарушение авторских прав'),
    _Reason('other', 'Другое'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Причина',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 12),
        RadioGroup<String>(
          groupValue: selectedReason,
          onChanged: (v) {
            if (v == null) return;
            onReasonChanged(v);
          },
          child: Column(
            children: _reasons
                .map(
                  (r) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    minLeadingWidth: 0,
                    horizontalTitleGap: 0,
                    leading: Radio<String>(value: r.id),
                    title: Text(r.label),
                    onTap: () => onReasonChanged(r.id),
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ],
    );
  }
}

class _Reason {
  const _Reason(this.id, this.label);
  final String id;
  final String label;
}

