import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/datasources/map_remote_datasource.dart';
import '../../domain/entities/featured_seller.dart';

/// Bottom sheet for placing/upgrading a Featured Seller bid.
class FeaturedBidSheet extends StatefulWidget {
  const FeaturedBidSheet({
    super.key,
    required this.dataSource,
    this.currentFeatured,
    this.myCurrentBid,
    this.onBidPlaced,
  });

  final MapRemoteDataSource dataSource;
  final FeaturedSeller? currentFeatured;
  final int? myCurrentBid;
  final void Function(int newBalance)? onBidPlaced;

  @override
  State<FeaturedBidSheet> createState() => _FeaturedBidSheetState();
}

class _FeaturedBidSheetState extends State<FeaturedBidSheet> {
  final _controller = TextEditingController();
  bool _loading = false;
  int? _balance;
  String? _error;

  int get _topBid => widget.currentFeatured?.bidAmount ?? 0;
  bool get _iAmLeader =>
      widget.currentFeatured?.userId ==
      Supabase.instance.client.auth.currentUser?.id;
  int get _minBid => _iAmLeader ? (_topBid + 1) : _topBid == 0 ? 200 : _topBid + 50;

  @override
  void initState() {
    super.initState();
    _controller.text = _minBid.toString();
    _loadBalance();
  }

  @override
  void dispose() {
    _controller.dispose();
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
      setState(() => _balance = (row?['qarmet_balance'] as num?)?.toInt() ?? 0);
    } catch (_) {}
  }

  Future<void> _placeBid() async {
    final amount = int.tryParse(_controller.text.trim());
    if (amount == null || amount < _minBid) {
      setState(() => _error = 'Минимальная ставка: $_minBid Qarmet');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.dataSource.placeFeaturedBid(amount);
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onBidPlaced?.call(result.newBalance);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ставка ${result.bidAmount} Qarmet принята! Баланс: ${result.newBalance} Qarmet',
          ),
          backgroundColor: const Color(0xFF16A34A),
        ),
      );
    } on FeaturedBidException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.userMessage;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Ошибка. Попробуйте позже.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cost = (int.tryParse(_controller.text.trim()) ?? _minBid) -
        (widget.myCurrentBid ?? 0);
    final displayCost = cost.clamp(0, 999999);

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
          // Title row
          Row(
            children: [
              const Text('🏆', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Продавец дня',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Ваш профиль — первое, что видят все на карте',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              if (_balance != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
          // Current leader card
          if (widget.currentFeatured != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.emoji_events_rounded,
                      color: Color(0xFFF59E0B), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Текущий лидер',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey)),
                        Text(
                          _iAmLeader
                              ? 'Вы — лидер!'
                              : widget.currentFeatured!.sellerName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${widget.currentFeatured!.bidAmount} Qarmet',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFF59E0B)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          // Rules info chips
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _InfoChip('Мин. ставка: $_minBid Q', Icons.arrow_upward_rounded),
              const _InfoChip('80% возврат если обогнали', Icons.undo_rounded),
              const _InfoChip('Сброс в полночь UTC', Icons.schedule_rounded),
            ],
          ),
          const SizedBox(height: 16),
          // Bid input
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _controller,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Ваша ставка (Qarmet)',
                    hintText: '$_minBid',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    suffixText: 'Q',
                    errorText: _error,
                  ),
                  onChanged: (_) {
                    setState(() => _error = null);
                  },
                ),
              ),
              const SizedBox(width: 10),
              // Quick-add buttons
              Column(
                children: [
                  _QuickAddButton(
                    label: '+50',
                    onTap: () {
                      final v = int.tryParse(_controller.text) ?? _minBid;
                      _controller.text = (v + 50).toString();
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 6),
                  _QuickAddButton(
                    label: '+100',
                    onTap: () {
                      final v = int.tryParse(_controller.text) ?? _minBid;
                      _controller.text = (v + 100).toString();
                      setState(() {});
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Cost summary
          if (displayCost > 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF86EFAC)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 16, color: Color(0xFF16A34A)),
                  const SizedBox(width: 8),
                  Text(
                    'Спишется: $displayCost Qarmet',
                    style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF166534),
                        fontWeight: FontWeight.w600),
                  ),
                  if (widget.myCurrentBid != null && widget.myCurrentBid! > 0) ...[
                    const SizedBox(width: 4),
                    Text(
                      '(уже внесено ${widget.myCurrentBid})',
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF4ADE80)),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 16),
          // Submit
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _loading ? null : _placeBid,
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
                          color: Colors.white, strokeWidth: 2),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('🏆', style: TextStyle(fontSize: 16)),
                        const SizedBox(width: 8),
                        Text(
                          _iAmLeader
                              ? 'Укрепить позицию'
                              : 'Занять место продавца дня',
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

class _InfoChip extends StatelessWidget {
  const _InfoChip(this.label, this.icon);
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.grey.shade600),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
        ],
      ),
    );
  }
}

class _QuickAddButton extends StatelessWidget {
  const _QuickAddButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700),
        ),
      ),
    );
  }
}
