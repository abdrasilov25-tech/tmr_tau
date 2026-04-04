import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/services/payment_service.dart';
import '../../domain/entities/qarmet_promotion_history_item.dart';
import '../../domain/entities/qarmet_product.dart';
import '../bloc/payment_cubit.dart';

/// Акценты витрины Qarmet (золото монеты + глубокий индиго).
class _QarmetBrand {
  static const gold = Color(0xFFFBBF24);
  static const goldDeep = Color(0xFFD97706);
  static const midnight = Color(0xFF0F172A);
  static const indigo = Color(0xFF312E81);
  static const violet = Color(0xFF5B21B6);
}

class QarmetWalletPage extends StatefulWidget {
  const QarmetWalletPage({super.key});

  @override
  State<QarmetWalletPage> createState() => _QarmetWalletPageState();
}

class _QarmetWalletPageState extends State<QarmetWalletPage>
    with TickerProviderStateMixin {
  _HistoryFilter _historyFilter = _HistoryFilter.all;

  late final AnimationController _coinDrift;
  late final AnimationController _heroPulse;

  @override
  void initState() {
    super.initState();
    _coinDrift = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat(reverse: true);
    _heroPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<PaymentCubit>().initStore();
    });
  }

  @override
  void dispose() {
    _coinDrift.dispose();
    _heroPulse.dispose();
    super.dispose();
  }

  List<QarmetPromotionHistoryItem> _filterHistory(
    List<QarmetPromotionHistoryItem> items,
  ) {
    switch (_historyFilter) {
      case _HistoryFilter.all:
        return items;
      case _HistoryFilter.active:
        return items.where((e) => e.hasAnyPromotion).toList();
      case _HistoryFilter.completed:
        return items.where((e) => !e.hasAnyPromotion).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
        backgroundColor: scheme.surface,
        appBar: AppBar(
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: scheme.onSurface,
          centerTitle: true,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.monetization_on_rounded,
                  color: _QarmetBrand.gold, size: 22),
              const SizedBox(width: 8),
              Text(
                'Qarmet',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
              ),
            ],
          ),
        ),
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomCenter,
              colors: [
                _QarmetBrand.gold.withValues(alpha: 0.12),
                scheme.primaryContainer.withValues(alpha: 0.18),
                scheme.surface,
              ],
              stops: const [0.0, 0.15, 0.45],
            ),
          ),
          child: BlocConsumer<PaymentCubit, PaymentUiState>(
          buildWhen: (prev, next) {
            final dataChanged = prev.balance != next.balance ||
                prev.catalog != next.catalog ||
                prev.isOfficialPageActive != next.isOfficialPageActive ||
                prev.cosmeticsLifetimeUnlocked !=
                    next.cosmeticsLifetimeUnlocked ||
                prev.promotionHistory != next.promotionHistory;
            final loadingChanged =
                (prev.status == PaymentUiStatus.loading) !=
                    (next.status == PaymentUiStatus.loading);
            final purchaseTargetChanged =
                prev.purchasingQarmetProductId !=
                    next.purchasingQarmetProductId;
            final storeStateChanged =
                prev.isStoreReady != next.isStoreReady ||
                prev.storeInitError != next.storeInitError;
            return dataChanged ||
                loadingChanged ||
                purchaseTargetChanged ||
                storeStateChanged;
          },
          listener: (context, state) {
            if (state.status == PaymentUiStatus.error ||
                state.status == PaymentUiStatus.cancelled) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.message ?? 'Операция не выполнена'),
                ),
              );
            } else if (state.status == PaymentUiStatus.success) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Операция выполнена')),
              );
            }
          },
          builder: (context, state) {
            final loading = state.status == PaymentUiStatus.loading;
            final filtered = _filterHistory(state.promotionHistory);
            // Каталог пакетов из кода (PaymentService) — запасной вариант, если в state ещё пусто.
            final catalog = state.catalog.isNotEmpty
                ? state.catalog
                : context.read<PaymentService>().catalog;
            final bestPricePerQarmet = catalog.isEmpty
                ? null
                : catalog
                    .map((e) => e.pricePerQarmet)
                    .reduce((a, b) => a < b ? a : b);
            // Одна карточка «лучшая цена» при равенстве KZT/Qarmet у нескольких пакетов.
            String? bestDealProductId;
            if (bestPricePerQarmet != null) {
              for (final p in catalog) {
                if ((p.pricePerQarmet - bestPricePerQarmet).abs() < 0.0001) {
                  bestDealProductId = p.productId;
                  break;
                }
              }
            }
            return RefreshIndicator(
              onRefresh: () => context
                  .read<PaymentCubit>()
                  .refreshWallet(forceRefresh: true),
              color: _QarmetBrand.goldDeep,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  _QarmetHeroBalance(
                    state: state,
                    showWalletProgress: state.isWalletWideBusy,
                    pulse: _heroPulse,
                  ),
                  const SizedBox(height: 20),
                  _AnimatedQarmetCoinShowcase(drift: _coinDrift),
                  const SizedBox(height: 20),
                  _WalletValueStrip(),
                  const SizedBox(height: 22),
                  _SectionTitle(
                    icon: Icons.shopping_bag_rounded,
                    title: 'Пополнить баланс',
                    subtitle:
                        'Больше Qarmet — больше видимости ваших товаров в ленте',
                  ),
                  const SizedBox(height: 12),
                  if (state.storeInitError != null) ...[
                    _StoreErrorBanner(
                      error: state.storeInitError!,
                      onRetry: () => context.read<PaymentCubit>().retryInitStore(),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (!state.isStoreReady) ...[
                    const _StoreConnectingHint(),
                    const SizedBox(height: 10),
                  ],
                  ...catalog.map(
                    (pack) => _QarmetPackageCard(
                      pack: pack,
                      isPurchasingThisPack:
                          state.purchasingQarmetProductId == pack.productId,
                      canTapBuy: state.canTapBuyQarmetPackage(pack.productId),
                      isBestPricePackage: bestDealProductId == pack.productId,
                      onBuy: () => context
                          .read<PaymentCubit>()
                          .buyQarmetPackage(pack.productId),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _PromotionHintBanner(),
                  const SizedBox(height: 24),
                  _SectionTitle(
                    icon: Icons.history_rounded,
                    title: 'История продвижений',
                    subtitle: 'Товары, для которых вы тратили Qarmet',
                  ),
                  const SizedBox(height: 8),
                  _HistoryFilterBar(
                    value: _historyFilter,
                    onChanged: (v) => setState(() => _historyFilter = v),
                    activeCount: state.promotionHistory
                        .where((e) => e.hasAnyPromotion)
                        .length,
                    completedCount: state.promotionHistory
                        .where((e) => !e.hasAnyPromotion)
                        .length,
                  ),
                  const SizedBox(height: 10),
                  if (state.promotionHistory.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(
                          alpha: 0.5,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            color: scheme.primary.withValues(alpha: 0.7),
                            size: 28,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              'Пока нет продвижений. Купите Qarmet выше и поднимите товар в топ.',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    height: 1.45,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (filtered.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(
                          alpha: 0.5,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        _historyFilter == _HistoryFilter.active
                            ? 'Нет активных продвижений. Переключитесь на «Завершённые» или «Все».'
                            : _historyFilter == _HistoryFilter.completed
                                ? 'Нет завершённых продвижений — всё ещё активно или истории пока нет.'
                                : 'Список пуст.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              height: 1.45,
                            ),
                      ),
                    ),
                  ...filtered.map(
                    (item) =>
                        _PromotionHistoryCard(item: item, loading: loading),
                  ),
                ],
              ),
            );
          },
        ),
        ),
    );
  }
}

enum _HistoryFilter { all, active, completed }

class _HistoryFilterBar extends StatelessWidget {
  const _HistoryFilterBar({
    required this.value,
    required this.onChanged,
    required this.activeCount,
    required this.completedCount,
  });

  final _HistoryFilter value;
  final ValueChanged<_HistoryFilter> onChanged;
  final int activeCount;
  final int completedCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<_HistoryFilter>(
          segments: [
            const ButtonSegment<_HistoryFilter>(
              value: _HistoryFilter.all,
              label: Text('Все'),
            ),
            ButtonSegment<_HistoryFilter>(
              value: _HistoryFilter.active,
              label: Text('Активные ($activeCount)'),
            ),
            ButtonSegment<_HistoryFilter>(
              value: _HistoryFilter.completed,
              label: Text('Завершённые ($completedCount)'),
            ),
          ],
          selected: {value},
          onSelectionChanged: (set) => onChanged(set.first),
        ),
      ],
    );
  }
}

class _PromotionHistoryCard extends StatelessWidget {
  const _PromotionHistoryCard({required this.item, required this.loading});

  final QarmetPromotionHistoryItem item;
  final bool loading;

  static String _formatUntil(DateTime? t, {required bool ended}) {
    if (t == null) return ended ? 'нет данных' : '';
    final d = t.toLocal();
    final date =
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';
    final time =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return ended ? 'было до $date $time' : 'до $date $time';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _promoChip(
                  context,
                  label: 'В топ',
                  active: item.isTopActive,
                  until: item.promoTopUntil,
                  activeColor: const Color(0xFF1D4ED8),
                  activeBg: const Color(0xFFE8EFFF),
                ),
                _promoChip(
                  context,
                  label: 'Срочно',
                  active: item.isUrgentActive,
                  until: item.promoUrgentUntil,
                  activeColor: const Color(0xFFEA580C),
                  activeBg: const Color(0xFFFFF4ED),
                ),
                _promoChip(
                  context,
                  label: 'Выделение',
                  active: item.isHighlightActive,
                  until: item.promoHighlightUntil,
                  activeColor: const Color(0xFF7C3AED),
                  activeBg: const Color(0xFFF3E8FF),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: loading
                      ? null
                      : () => context.read<PaymentCubit>().spendTopPromotion(
                          item.productId,
                        ),
                  child: const Text('В топ · 1'),
                ),
                OutlinedButton(
                  onPressed: loading
                      ? null
                      : () => context.read<PaymentCubit>().spendUrgentPromotion(
                          item.productId,
                        ),
                  child: const Text('Срочно · 1'),
                ),
                OutlinedButton(
                  onPressed: loading
                      ? null
                      : () => context
                            .read<PaymentCubit>()
                            .spendHighlightPromotion(item.productId),
                  child: const Text('Выделение · 1'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _promoChip(
    BuildContext context, {
    required String label,
    required bool active,
    required DateTime? until,
    required Color activeColor,
    required Color activeBg,
  }) {
    final hadSlot = until != null || active;
    if (!hadSlot) {
      return const SizedBox.shrink();
    }
    final text = active
        ? '$label · ${_formatUntil(until, ended: false)}'
        : (until != null
              ? '$label · ${_formatUntil(until, ended: true)}'
              : label);
    final fg = active ? activeColor : Colors.grey.shade700;
    final bg = active ? activeBg : Colors.grey.shade200;
    final border = active
        ? activeColor.withValues(alpha: 0.35)
        : Colors.grey.shade400;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: fg,
          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                scheme.primaryContainer,
                scheme.secondaryContainer.withValues(alpha: 0.6),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: scheme.primary.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, color: scheme.primary, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.35,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QarmetHeroBalance extends StatelessWidget {
  const _QarmetHeroBalance({
    required this.state,
    required this.showWalletProgress,
    required this.pulse,
  });

  final PaymentUiState state;
  final bool showWalletProgress;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _QarmetBrand.midnight,
                    _QarmetBrand.indigo,
                    _QarmetBrand.violet.withValues(alpha: 0.95),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: -36,
            top: -48,
            child: AnimatedBuilder(
              animation: pulse,
              builder: (context, _) {
                final w = 140.0 + 24 * pulse.value;
                return Container(
                  width: w,
                  height: w,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        _QarmetBrand.gold.withValues(
                          alpha: 0.22 + 0.12 * pulse.value,
                        ),
                        Colors.transparent,
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned(
            left: -30,
            bottom: -24,
            child: AnimatedBuilder(
              animation: pulse,
              builder: (context, _) {
                return Container(
                  width: 100 + 16 * (1 - pulse.value),
                  height: 100 + 16 * (1 - pulse.value),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF22D3EE).withValues(alpha: 0.08),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.account_balance_wallet_outlined,
                            color: _QarmetBrand.gold,
                            size: 17,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Ваш баланс',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.92),
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.auto_awesome_rounded,
                      color: _QarmetBrand.gold.withValues(alpha: 0.85),
                      size: 22,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  '${state.balance}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 48,
                    height: 1.02,
                    letterSpacing: -1.5,
                  ),
                ),
                Text(
                  'Qarmet · внутренняя валюта TMR TAU',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        state.isOfficialPageActive
                            ? Icons.verified_rounded
                            : Icons.star_outline_rounded,
                        color: state.isOfficialPageActive
                            ? _QarmetBrand.gold
                            : Colors.white54,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          state.isOfficialPageActive
                              ? 'Official Page активна — каждый месяц +20 и +5 Qarmet'
                              : 'Подключите Official Page — статус профиля и ежемесячные монеты',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.88),
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (showWalletProgress) ...[
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: const LinearProgressIndicator(
                      minHeight: 4,
                      backgroundColor: Colors.white24,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(_QarmetBrand.gold),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedQarmetCoinShowcase extends StatelessWidget {
  const _AnimatedQarmetCoinShowcase({required this.drift});

  final Animation<double> drift;

  static Widget _coinImage(double size) {
    return ClipOval(
      child: Image.asset(
        'assets/qarmet_coin_nominal.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: size,
            height: size,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              'Q',
              style: TextStyle(
                color: _QarmetBrand.gold,
                fontWeight: FontWeight.w900,
                fontSize: size * 0.38,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.surfaceContainerHighest.withValues(alpha: 0.65),
            scheme.surfaceContainerLow.withValues(alpha: 0.9),
          ],
        ),
        border: Border.all(
          color: _QarmetBrand.gold.withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: _QarmetBrand.goldDeep.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 118,
            height: 118,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedBuilder(
                  animation: drift,
                  builder: (context, _) {
                    final t = drift.value * math.pi * 2;
                    final glow = 0.28 + 0.14 * math.sin(t);
                    return Container(
                      width: 108,
                      height: 108,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _QarmetBrand.gold.withValues(alpha: glow),
                            blurRadius: 28,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    );
                  },
                ),
                AnimatedBuilder(
                  animation: drift,
                  builder: (context, _) {
                    final t = drift.value;
                    final dy = 5 * math.sin(t * math.pi * 2);
                    final rot = 0.035 * math.sin(t * math.pi * 2 + 1);
                    return Transform.translate(
                      offset: Offset(0, dy),
                      child: Transform.rotate(
                        angle: rot,
                        child: Transform.scale(
                          scale: 1.0 + 0.035 * math.sin(t * math.pi * 2),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _QarmetBrand.gold.withValues(alpha: 0.55),
                                width: 2.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  blurRadius: 12,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: _coinImage(96),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _QarmetBrand.gold.withValues(alpha: 0.25),
                        _QarmetBrand.goldDeep.withValues(alpha: 0.15),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Номинал 1 Qarmet',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      letterSpacing: 0.4,
                      color: Color(0xFF78350F),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Монеты для продвижения',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Поднимайте объявления в топ, выделяйте срочность и оформляйте профиль — всё через Qarmet.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        height: 1.4,
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletValueStrip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        _valueTile(
          context,
          icon: Icons.savings_outlined,
          title: 'Честная цена',
          body:
              'Пакеты ниже — лучший способ купить Qarmet. Выберите объём и оплатите в один тап.',
          accent: scheme.primary,
        ),
        const SizedBox(height: 10),
        _valueTile(
          context,
          icon: Icons.storefront_outlined,
          title: 'Планы продавца',
          body:
              'Базовый: до 3 товаров · Стандарт: до 20 + ежемесячные Qarmet · Про: безлимит и расширенная статистика.',
          accent: _QarmetBrand.violet,
        ),
      ],
    );
  }

  Widget _valueTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String body,
    required Color accent,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: accent.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        height: 1.4,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PromotionHintBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFFFBEB),
            const Color(0xFFFEF3C7).withValues(alpha: 0.65),
          ],
        ),
        border: Border.all(color: const Color(0xFFFCD34D).withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: _QarmetBrand.gold.withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.tips_and_updates_rounded,
              color: Color(0xFFB45309),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '«В топ», «Срочно» и «Выделение» для товара — по 1 Qarmet за запуск. '
              'Пополните баланс и дайте объявлениям больше просмотров.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.45,
                    color: const Color(0xFF78350F),
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Пока StoreKit не ответил — пакеты видны, кнопки «Купить» неактивны ([canTapBuy]).
class _StoreConnectingHint extends StatelessWidget {
  const _StoreConnectingHint();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Подключаемся к магазину… Кнопки покупки заработают через несколько секунд.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StoreErrorBanner extends StatelessWidget {
  const _StoreErrorBanner({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.red.shade200),
      ),
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline_rounded,
                    color: Colors.red.shade700, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Магазин покупок недоступен',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              error,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.red.shade800,
                  ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Повторить'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                  side: BorderSide(color: Colors.red.shade300),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QarmetPackageCard extends StatelessWidget {
  const _QarmetPackageCard({
    required this.pack,
    required this.isPurchasingThisPack,
    required this.canTapBuy,
    required this.isBestPricePackage,
    required this.onBuy,
  });

  final QarmetProduct pack;
  final bool isPurchasingThisPack;
  final bool canTapBuy;
  final bool isBestPricePackage;
  final VoidCallback onBuy;

  String get _packTitle {
    switch (pack.productId) {
      case PaymentService.promotionStartProductId:
        return 'Легкий старт';
      case PaymentService.promotionPremiumProductId:
        return 'Новичок';
      case PaymentService.promotionBusinessProductId:
        return 'Лучшая цена';
      case PaymentService.promotionEliteProductId:
        return 'Элита';
      case PaymentService.officialPageProductId:
        return 'Донатер';
      default:
        return pack.title;
    }
  }

  String get _marketingNote {
    switch (pack.productId) {
      case PaymentService.promotionStartProductId:
        return 'Минимальная цена входа. Быстрый старт продвижения.';
      case PaymentService.promotionPremiumProductId:
        return 'Для тех, кто только начинает и хочет буст с бонусом.';
      case PaymentService.promotionBusinessProductId:
        return 'Максимум Qarmet за ваши деньги. Самый выгодный пакет.';
      case PaymentService.promotionEliteProductId:
        return '800 Qarmet — максимальный пакет для активных пользователей.';
      case PaymentService.officialPageProductId:
        return 'Инстаграм-галочка, статус профиля и ежемесячные начисления.';
      default:
        return 'Пакет Qarmet для продвижения и выделения.';
    }
  }

  String get _badgeText {
    switch (pack.productId) {
      case PaymentService.promotionStartProductId:
        return 'Низкая цена';
      case PaymentService.promotionPremiumProductId:
        return 'Хит для старта';
      case PaymentService.promotionBusinessProductId:
        return 'Топ выгода';
      case PaymentService.promotionEliteProductId:
        return 'Макс пакет';
      case PaymentService.officialPageProductId:
        return 'Статус';
      default:
        return 'Пакет';
    }
  }

  Color get _badgeColor {
    switch (pack.productId) {
      case PaymentService.promotionStartProductId:
        return const Color(0xFF0891B2);
      case PaymentService.promotionPremiumProductId:
        return const Color(0xFF7C3AED);
      case PaymentService.promotionBusinessProductId:
        return const Color(0xFF1D4ED8);
      case PaymentService.promotionEliteProductId:
        return const Color(0xFFD97706);
      case PaymentService.officialPageProductId:
        return const Color(0xFFBE123C);
      default:
        return const Color(0xFF334155);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final borderColor = isBestPricePackage
        ? const Color(0xFF2563EB)
        : _badgeColor.withValues(alpha: 0.35);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: _badgeColor.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Material(
          color: scheme.surfaceContainerLow,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: borderColor, width: isBestPricePackage ? 2 : 1),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.surface,
                  scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _badgeColor.withValues(alpha: 0.2),
                              _badgeColor.withValues(alpha: 0.06),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: _badgeColor.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          _badgeText,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: _badgeColor,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      if (isBestPricePackage) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEF2FF),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.local_fire_department_rounded,
                                size: 14,
                                color: Color(0xFF4F46E5),
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Выгодно',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF4F46E5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              _badgeColor.withValues(alpha: 0.2),
                              _badgeColor.withValues(alpha: 0.05),
                            ],
                          ),
                        ),
                        child: Icon(
                          pack.isSubscription
                              ? Icons.workspace_premium_rounded
                              : Icons.bolt_rounded,
                          color: _badgeColor,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _packTitle,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.2,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _marketingNote,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    height: 1.4,
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(
                        alpha: 0.65,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.monetization_on_rounded,
                              size: 18,
                              color: _QarmetBrand.goldDeep,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${pack.totalQarmet} Qarmet',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            Text(
                              ' · ${pack.baseQarmet}+${pack.bonusQarmet} бонус',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${pack.priceKzt} ₸ · ${pack.pricePerQarmet.toStringAsFixed(2)} ₸ за 1 Qarmet',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        if (pack.isSubscription) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Каждый месяц: +20 и +5 Qarmet, галочка и привилегии профиля.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  height: 1.35,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        elevation: 0,
                        backgroundColor: _badgeColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: canTapBuy ? onBuy : null,
                      child: isPurchasingThisPack
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.shopping_cart_rounded, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  pack.isSubscription
                                      ? 'Подключить за ${pack.priceKzt} ₸'
                                      : 'Купить за ${pack.priceKzt} ₸',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
