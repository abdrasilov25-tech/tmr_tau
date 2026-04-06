import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/datasources/map_remote_datasource.dart';
import '../../domain/entities/mystery_spot.dart';

/// Animated reveal sheet for Mystery Spot.
class MysterySpotRevealSheet extends StatefulWidget {
  const MysterySpotRevealSheet({
    super.key,
    required this.spot,
    required this.dataSource,
    this.onRevealed,
  });

  final MysterySpot spot;
  final MapRemoteDataSource dataSource;
  final VoidCallback? onRevealed;

  @override
  State<MysterySpotRevealSheet> createState() =>
      _MysterySpotRevealSheetState();
}

enum _RevealState { idle, counting, revealed, alreadyClaimed }

class _MysterySpotRevealSheetState extends State<MysterySpotRevealSheet>
    with TickerProviderStateMixin {
  _RevealState _state = _RevealState.idle;
  int _countdown = 3;
  MysterySpotRevealResult? _result;
  Timer? _timer;

  late final AnimationController _scaleCtrl = AnimationController(
    duration: const Duration(milliseconds: 600),
    vsync: this,
  );
  late final Animation<double> _scaleAnim =
      CurvedAnimation(parent: _scaleCtrl, curve: Curves.elasticOut);

  @override
  void initState() {
    super.initState();
    if (widget.spot.alreadyClaimed) {
      _state = _RevealState.alreadyClaimed;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scaleCtrl.dispose();
    super.dispose();
  }

  Future<void> _startReveal() async {
    setState(() {
      _state = _RevealState.counting;
      _countdown = 3;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (_countdown > 1) {
        setState(() => _countdown--);
      } else {
        t.cancel();
        await _doReveal();
      }
    });
  }

  Future<void> _doReveal() async {
    try {
      final result =
          await widget.dataSource.revealMysterySpot(widget.spot.id);
      if (!mounted) return;
      setState(() {
        _result = result;
        _state = result.alreadyClaimed
            ? _RevealState.alreadyClaimed
            : _RevealState.revealed;
      });
      if (!result.alreadyClaimed) {
        _scaleCtrl.forward(from: 0);
        widget.onRevealed?.call();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _state = _RevealState.idle);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть. Попробуйте позже.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _buildContent(),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return switch (_state) {
      _RevealState.idle => _buildIdle(),
      _RevealState.counting => _buildCounting(),
      _RevealState.revealed => _buildRevealed(),
      _RevealState.alreadyClaimed => _buildAlreadyClaimed(),
    };
  }

  Widget _buildIdle() {
    final spot = widget.spot;
    return Column(
      children: [
        const Text('❓', style: TextStyle(fontSize: 64)),
        const SizedBox(height: 12),
        const Text(
          'Mystery Spot',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          spot.isSellerSponsored && spot.sellerName != null
              ? 'Спонсировано: ${spot.sellerName}'
              : 'Ежедневное тайное место',
          style: const TextStyle(color: Colors.white54, fontSize: 13),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.toll_rounded,
                size: 16, color: Color(0xFFF59E0B)),
            const SizedBox(width: 6),
            Text(
              '+${spot.qarmetReward} Qarmet',
              style: const TextStyle(
                color: Color(0xFFF59E0B),
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ]),
        ),
        if (spot.isSellerSponsored && spot.sellerOffer != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(children: [
              const Text('🎁', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  spot.sellerOffer!,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _startReveal,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text(
              'Открыть тайник',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCounting() {
    return Column(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, anim) =>
              ScaleTransition(scale: anim, child: child),
          child: Text(
            '$_countdown',
            key: ValueKey(_countdown),
            style: const TextStyle(
              color: Color(0xFFF59E0B),
              fontSize: 96,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Открываем тайник...',
          style: TextStyle(color: Colors.white54, fontSize: 16),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildRevealed() {
    final result = _result!;
    final isSeller = result.isSellerSponsored;

    return ScaleTransition(
      scale: _scaleAnim,
      child: Column(
        children: [
          Text(
            isSeller ? '🎉' : '💰',
            style: const TextStyle(fontSize: 72),
          ),
          const SizedBox(height: 12),
          const Text(
            'Тайник открыт!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          // Qarmet reward
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.toll_rounded,
                  size: 28, color: Color(0xFFF59E0B)),
              const SizedBox(width: 10),
              Text(
                '+${result.qarmetAwarded} Qarmet',
                style: const TextStyle(
                  color: Color(0xFFF59E0B),
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          Text(
            'Баланс: ${result.newBalance} Qarmet',
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
          // Seller offer
          if (isSeller && result.sellerOffer != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🎁 Предложение от спонсора',
                      style: TextStyle(color: Colors.white54, fontSize: 11)),
                  const SizedBox(height: 6),
                  Text(
                    result.sellerOffer!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (result.productId != null) ...[
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).pop();
                        context.push('/product/${result.productId}');
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white12,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Перейти к объявлению →',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white24),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Отлично!'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlreadyClaimed() {
    return Column(
      children: [
        const Text('🔒', style: TextStyle(fontSize: 64)),
        const SizedBox(height: 12),
        const Text(
          'Уже открыт сегодня',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Новый тайник появится завтра в 00:00 UTC',
          style: TextStyle(color: Colors.white54),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white24),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Понятно'),
          ),
        ),
      ],
    );
  }
}

/// Sheet for sellers to purchase Mystery Spot slot for tomorrow.
class MysterySpotPurchaseSheet extends StatefulWidget {
  const MysterySpotPurchaseSheet({
    super.key,
    required this.dataSource,
    required this.productId,
    required this.productTitle,
    this.onPurchased,
  });

  final MapRemoteDataSource dataSource;
  final String productId;
  final String productTitle;
  final VoidCallback? onPurchased;

  @override
  State<MysterySpotPurchaseSheet> createState() =>
      _MysterySpotPurchaseSheetState();
}

class _MysterySpotPurchaseSheetState
    extends State<MysterySpotPurchaseSheet> {
  final _offerCtrl = TextEditingController();
  int _bid = 200;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _offerCtrl.dispose();
    super.dispose();
  }

  Future<void> _purchase() async {
    if (_offerCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Введите текст предложения для посетителей');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.dataSource.purchaseMysterySpotSlot(
        offerText: _offerCtrl.text.trim(),
        productId: widget.productId,
        bidAmount: _bid,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onPurchased?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Mystery Spot куплен на ${result.spotDate}! Баланс: ${result.newBalance} Q'),
          backgroundColor: const Color(0xFF16A34A),
        ),
      );
    } on MysterySpotException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.userMessage;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Reward users will receive (15% of bid)
    final userReward = (_bid * 15) ~/ 100;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              const Text('❓', style: TextStyle(fontSize: 28)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Mystery Spot — завтра',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(widget.productTitle,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF9C3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: const Text(
                '❓ знак появится на карте завтра. Пользователи, которые найдут и откроют его, увидят ваш оффер и получат Qarmet-награду. Слот — 1 продавец в день.',
                style: TextStyle(fontSize: 12, color: Color(0xFF92400E)),
              ),
            ),
            const SizedBox(height: 16),
            // Offer text
            TextField(
              controller: _offerCtrl,
              decoration: InputDecoration(
                labelText: 'Предложение для нашедших тайник *',
                hintText: 'Скидка 15% при показе этого экрана сегодня',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.local_offer_outlined),
                errorText: _error,
              ),
              maxLines: 2,
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 16),
            // Bid selector
            const Text('Ставка (Qarmet)',
                style:
                    TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final v in [200, 400, 600, 1000])
                GestureDetector(
                  onTap: () => setState(() => _bid = v),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: _bid == v
                          ? const Color(0xFF1A1A1A)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('$v Q',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _bid == v
                              ? Colors.white
                              : Colors.grey.shade700,
                        )),
                  ),
                ),
            ]),
            const SizedBox(height: 16),
            // Summary
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(children: [
                _SummaryRow('Ваша ставка', '$_bid Qarmet'),
                const SizedBox(height: 6),
                _SummaryRow('Награда нашедшим',
                    '+$userReward Qarmet (15%)'),
                const Divider(height: 16),
                _SummaryRow('Слот', 'Завтра · весь день'),
              ]),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _loading ? null : _purchase,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1A1A1A),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Text(
                        'Купить Mystery Spot за $_bid Qarmet',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
        Text(value,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 13)),
      ],
    );
  }
}
