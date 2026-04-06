import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/datasources/map_remote_datasource.dart';

/// Sheet for purchasing a Zone Takeover.
class ZonePurchaseSheet extends StatefulWidget {
  const ZonePurchaseSheet({
    super.key,
    required this.dataSource,
    required this.currentLat,
    required this.currentLng,
    this.onPurchased,
  });

  final MapRemoteDataSource dataSource;
  final double currentLat;
  final double currentLng;
  final VoidCallback? onPurchased;

  @override
  State<ZonePurchaseSheet> createState() => _ZonePurchaseSheetState();
}

class _ZonePurchaseSheetState extends State<ZonePurchaseSheet> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _offerCtrl = TextEditingController();

  int _radiusMeters = 500;
  int _durationDays = 7;
  Color _brandColor = const Color(0xFF2563EB);
  bool _loading = false;
  int? _balance;
  String? _error;

  static const _colorOptions = [
    Color(0xFF2563EB), // Blue
    Color(0xFF16A34A), // Green
    Color(0xFFF97316), // Orange
    Color(0xFFDC2626), // Red
    Color(0xFF7C3AED), // Purple
    Color(0xFF0891B2), // Cyan
    Color(0xFF1A1A1A), // Black
    Color(0xFFF59E0B), // Gold
  ];

  static const _pricingMatrix = {
    (500, 7): 2000,
    (500, 30): 6000,
    (1000, 7): 4000,
    (1000, 30): 12000,
  };

  int get _cost => _pricingMatrix[(_radiusMeters, _durationDays)] ?? 2000;

  @override
  void initState() {
    super.initState();
    _loadBalance();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _offerCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBalance() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;
      final row = await Supabase.instance.client
          .from('users')
          .select('qarmet_balance')
          .eq('id', uid)
          .maybeSingle();
      if (!mounted) return;
      setState(() =>
          _balance = (row?['qarmet_balance'] as num?)?.toInt() ?? 0);
    } catch (e) { debugPrint('$e'); }
  }

  Future<void> _purchase() async {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Введите название зоны');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.dataSource.purchaseMapZone(
        name: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        offerText: _offerCtrl.text.trim(),
        brandColor: _brandColor,
        latitude: widget.currentLat,
        longitude: widget.currentLng,
        radiusMeters: _radiusMeters,
        durationDays: _durationDays,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onPurchased?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Зона активирована! Баланс: ${result.newBalance} Qarmet'),
          backgroundColor: const Color(0xFF16A34A),
        ),
      );
    } on ZonePurchaseException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.userMessage;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Ошибка. Попробуйте позже.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Header
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _brandColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child:
                      Icon(Icons.radar_rounded, color: _brandColor, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Zone Takeover',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Ваш бренд виден всем в радиусе зоны',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                if (_balance != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF9C3),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.toll_rounded,
                            size: 14, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 4),
                        Text(
                          '$_balance Q',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF92400E),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            // Zone name
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: 'Название бизнеса / зоны *',
                hintText: 'Кофейня "Арома"',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                errorText: _error,
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 12),
            // Description
            TextField(
              controller: _descCtrl,
              decoration: InputDecoration(
                labelText: 'Описание (необязательно)',
                hintText: 'Лучший кофе в Алматы',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            // Offer text
            TextField(
              controller: _offerCtrl,
              decoration: InputDecoration(
                labelText: 'Акция для посетителей зоны',
                hintText: 'Скидка 10% при показе этого экрана',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.local_offer_outlined),
              ),
            ),
            const SizedBox(height: 20),
            // Brand color
            const Text('Цвет бренда',
                style:
                    TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              children: _colorOptions.map((c) {
                final selected = _brandColor == c;
                return GestureDetector(
                  onTap: () => setState(() => _brandColor = c),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? Colors.black
                            : Colors.transparent,
                        width: 2.5,
                      ),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                  color: c.withValues(alpha: 0.5),
                                  blurRadius: 8)
                            ]
                          : null,
                    ),
                    child: selected
                        ? const Icon(Icons.check_rounded,
                            color: Colors.white, size: 18)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            // Radius
            const Text('Радиус зоны',
                style:
                    TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 8),
            Row(
              children: [
                _OptionChip(
                  label: '500 м',
                  selected: _radiusMeters == 500,
                  onTap: () => setState(() => _radiusMeters = 500),
                ),
                const SizedBox(width: 10),
                _OptionChip(
                  label: '1 км',
                  selected: _radiusMeters == 1000,
                  onTap: () => setState(() => _radiusMeters = 1000),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Duration
            const Text('Длительность',
                style:
                    TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 8),
            Row(
              children: [
                _OptionChip(
                  label: '7 дней',
                  selected: _durationDays == 7,
                  onTap: () => setState(() => _durationDays = 7),
                ),
                const SizedBox(width: 10),
                _OptionChip(
                  label: '30 дней',
                  selected: _durationDays == 30,
                  onTap: () => setState(() => _durationDays = 30),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Cost summary
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _brandColor.withValues(alpha: 0.08),
                    _brandColor.withValues(alpha: 0.03),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: _brandColor.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_radiusMeters >= 1000 ? '1 км' : '500 м'} · $_durationDays дней',
                        style: const TextStyle(
                            fontSize: 13, color: Colors.grey),
                      ),
                      const Text('Итого:',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15)),
                    ],
                  ),
                  Text(
                    '$_cost Qarmet',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: _brandColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Submit
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _loading ? null : _purchase,
                style: FilledButton.styleFrom(
                  backgroundColor: _brandColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Text(
                        'Активировать зону',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1A1A1A) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: selected ? Colors.white : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }
}
