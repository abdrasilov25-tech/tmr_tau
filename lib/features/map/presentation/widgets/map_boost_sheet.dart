import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/datasources/map_remote_datasource.dart';

/// Bottom sheet for purchasing a map boost for a seller's product.
class MapBoostSheet extends StatefulWidget {
  const MapBoostSheet({
    super.key,
    required this.productId,
    required this.productTitle,
    required this.dataSource,
    this.onBoostPurchased,
  });

  final String productId;
  final String productTitle;
  final MapRemoteDataSource dataSource;
  final VoidCallback? onBoostPurchased;

  @override
  State<MapBoostSheet> createState() => _MapBoostSheetState();
}

class _MapBoostSheetState extends State<MapBoostSheet> {
  int _selectedLevel = 1;
  int _selectedDuration = 24;
  bool _loading = false;
  int? _currentBalance;

  static const _tiers = [
    _BoostTier(
      level: 1,
      name: 'Boost',
      description: 'Увеличенная метка + анимация пульса\nВыделяется среди обычных объявлений',
      costPer24h: 50,
      color: Color(0xFF2563EB),
      icon: Icons.rocket_launch_rounded,
    ),
    _BoostTier(
      level: 2,
      name: 'Top Zone',
      description: 'Золотая метка + закреплён в топе\nВидно при любом масштабе карты',
      costPer24h: 150,
      color: Color(0xFFF59E0B),
      icon: Icons.workspace_premium_rounded,
    ),
  ];

  static const _durations = [
    (hours: 24, label: '1 день'),
    (hours: 72, label: '3 дня'),
    (hours: 168, label: '7 дней'),
  ];

  @override
  void initState() {
    super.initState();
    _loadBalance();
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
      setState(() => _currentBalance = (row?['qarmet_balance'] as num?)?.toInt() ?? 0);
    } catch (e) { debugPrint('$e'); }
  }

  int get _totalCost {
    final tier = _tiers.firstWhere((t) => t.level == _selectedLevel);
    return tier.costPer24h * (_selectedDuration ~/ 24);
  }

  Future<void> _purchase() async {
    setState(() => _loading = true);
    try {
      final newBalance = await widget.dataSource.purchaseMapBoost(
        productId: widget.productId,
        boostLevel: _selectedLevel,
        durationHours: _selectedDuration,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onBoostPurchased?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Буст активирован! Баланс: $newBalance Qarmet'),
          backgroundColor: const Color(0xFF16A34A),
        ),
      );
    } on MapBoostException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.userMessage),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Произошла ошибка. Попробуйте позже.'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          Row(
            children: [
              const Icon(Icons.bolt_rounded, color: Color(0xFFF59E0B), size: 22),
              const SizedBox(width: 8),
              const Text(
                'Буст на карте',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (_currentBalance != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF9C3),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.toll_rounded, size: 14, color: Color(0xFFF59E0B)),
                      const SizedBox(width: 4),
                      Text(
                        '$_currentBalance Qarmet',
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
          const SizedBox(height: 4),
          Text(
            widget.productTitle,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 20),
          // Boost tier selection
          ...(_tiers.map((tier) => _TierCard(
                tier: tier,
                isSelected: _selectedLevel == tier.level,
                onTap: () => setState(() => _selectedLevel = tier.level),
              ))),
          const SizedBox(height: 16),
          // Duration selection
          const Text(
            'Длительность',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Row(
            children: _durations.map((d) {
              final isSelected = _selectedDuration == d.hours;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedDuration = d.hours),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF1A1A1A)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      d.label,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: isSelected ? Colors.white : Colors.grey.shade700,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          // Purchase button
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _loading ? null : _purchase,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1A1A1A),
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
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.bolt_rounded, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          'Активировать за $_totalCost Qarmet',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BoostTier {
  const _BoostTier({
    required this.level,
    required this.name,
    required this.description,
    required this.costPer24h,
    required this.color,
    required this.icon,
  });

  final int level;
  final String name;
  final String description;
  final int costPer24h;
  final Color color;
  final IconData icon;
}

class _TierCard extends StatelessWidget {
  const _TierCard({
    required this.tier,
    required this.isSelected,
    required this.onTap,
  });

  final _BoostTier tier;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? tier.color.withValues(alpha:0.06) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? tier.color : Colors.grey.shade200,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: tier.color.withValues(alpha:0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(tier.icon, color: tier.color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tier.name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: isSelected ? tier.color : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tier.description,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${tier.costPer24h}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: isSelected ? tier.color : Colors.black87,
                  ),
                ),
                Text(
                  'Qarmet/день',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                ),
              ],
            ),
            const SizedBox(width: 4),
            Icon(
              isSelected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: isSelected ? tier.color : Colors.grey.shade400,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
