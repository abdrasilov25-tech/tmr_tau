import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/services/payment_service.dart';
import '../../domain/entities/qarmet_promotion_history_item.dart';
import '../../domain/entities/qarmet_product.dart';
import '../bloc/payment_cubit.dart';

class QarmetWalletPage extends StatefulWidget {
  const QarmetWalletPage({super.key});

  @override
  State<QarmetWalletPage> createState() => _QarmetWalletPageState();
}

class _QarmetWalletPageState extends State<QarmetWalletPage> {
  _HistoryFilter _historyFilter = _HistoryFilter.all;

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
    return BlocProvider(
      create: (_) => PaymentCubit(context.read<PaymentService>())..initStore(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Qarmet кошелек'),
        ),
        body: BlocConsumer<PaymentCubit, PaymentUiState>(
          buildWhen: (prev, next) {
            final dataChanged = prev.balance != next.balance ||
                prev.catalog != next.catalog ||
                prev.isOfficialPageActive != next.isOfficialPageActive ||
                prev.promotionHistory != next.promotionHistory;
            final loadingChanged =
                (prev.status == PaymentUiStatus.loading) !=
                    (next.status == PaymentUiStatus.loading);
            return dataChanged || loadingChanged;
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
            final bestPricePerQarmet = state.catalog.isEmpty
                ? null
                : state.catalog
                    .map((e) => e.pricePerQarmet)
                    .reduce((a, b) => a < b ? a : b);
            return RefreshIndicator(
              onRefresh: () => context.read<PaymentCubit>().refreshWallet(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _BalanceCard(state: state, loading: loading),
                  const SizedBox(height: 14),
                  const _QarmetCoinNominalCard(),
                  const SizedBox(height: 10),
                  const _QarmetPriceExplain(),
                  const SizedBox(height: 10),
                  const _SellerPlansCard(),
                  const SizedBox(height: 10),
                  Text(
                    'Купить Qarmet',
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  if (state.catalog.isEmpty)
                    const _CatalogLoadingPlaceholder()
                  else
                    ...state.catalog.map(
                      (pack) => _QarmetPackageCard(
                        pack: pack,
                        loading: loading,
                        bestPricePerQarmet: bestPricePerQarmet,
                        onBuy: () => context
                            .read<PaymentCubit>()
                            .buyQarmetPackage(pack.productId),
                      ),
                    ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.shade200),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Продвижение товара (В топ / Срочно / Выделение) стоит 1 Qarmet за активацию.',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
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
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Пока нет продвигавшихся товаров. Когда поднимете товар в топ/срочно/выделение, он появится здесь.',
                      ),
                    )
                  else if (filtered.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _historyFilter == _HistoryFilter.active
                            ? 'Нет активных продвижений. Переключитесь на «Завершённые» или «Все».'
                            : _historyFilter == _HistoryFilter.completed
                            ? 'Нет завершённых продвижений — все ещё активны или истории пока нет.'
                            : 'Список пуст.',
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
        Text(
          'История продвижений',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
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

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.state, required this.loading});

  final PaymentUiState state;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFF0F172A),
            Color(0xFF1D4ED8),
            Color(0xFF22D3EE),
          ],
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Qarmet баланс',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 6),
          Text(
            '${state.balance}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 34,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            state.isOfficialPageActive
                ? 'official_page активна: каждый месяц начисляется 20 + 5 Qarmet'
                : 'Подписка official_page неактивна',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          if (loading) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(
              minHeight: 3,
              backgroundColor: Colors.white24,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ],
        ],
      ),
    );
  }
}

class _QarmetPriceExplain extends StatelessWidget {
  const _QarmetPriceExplain();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.local_offer_outlined,
            color: Colors.blue.shade700,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Цена Qarmet: 149 тг за 1 Qarmet.\n'
              'Выбирайте пакет ниже и нажмите «Купить».',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _QarmetCoinNominalCard extends StatelessWidget {
  const _QarmetCoinNominalCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              'assets/qarmet_coin_nominal.png',
              width: 88,
              height: 88,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  width: 88,
                  height: 88,
                  color: const Color(0xFF0F172A),
                  alignment: Alignment.center,
                  child: const Text(
                    '1\nQARMET',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Номинал валюты',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                const Text('1 QARMET'),
                const SizedBox(height: 2),
                Text(
                  'Официальный номинал внутри приложения',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SellerPlansCard extends StatelessWidget {
  const _SellerPlansCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.purple.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purple.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Подписка продавца',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text('Базовый: 3 активных товара'),
          const Text('Стандарт: до 20 товаров + Qarmet каждый месяц'),
          const Text('Про: безлимит + приоритет + расширенная статистика'),
          const SizedBox(height: 8),
          Text(
            'План назначается по профилю продавца. Если лимит достигнут, при публикации откроется этот экран.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _CatalogLoadingPlaceholder extends StatelessWidget {
  const _CatalogLoadingPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Expanded(child: Text('Загружаем пакеты Qarmet...')),
          ],
        ),
      ),
    );
  }
}

class _QarmetPackageCard extends StatelessWidget {
  const _QarmetPackageCard({
    required this.pack,
    required this.loading,
    required this.bestPricePerQarmet,
    required this.onBuy,
  });

  final QarmetProduct pack;
  final bool loading;
  final double? bestPricePerQarmet;
  final VoidCallback onBuy;

  String get _packTitle {
    switch (pack.productId) {
      case PaymentService.promotionStartProductId:
        return 'Легкий старт';
      case PaymentService.promotionPremiumProductId:
        return 'Новичок';
      case PaymentService.promotionBusinessProductId:
        return 'Лучшая цена';
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
      case PaymentService.officialPageProductId:
        return const Color(0xFFBE123C);
      default:
        return const Color(0xFF334155);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBest = bestPricePerQarmet != null &&
        (pack.pricePerQarmet - bestPricePerQarmet!).abs() < 0.0001;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isBest ? const Color(0xFF2563EB) : Colors.grey.shade300,
          width: isBest ? 1.4 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _badgeColor.withValues(alpha: 0.16),
                    _badgeColor.withValues(alpha: 0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _badgeColor.withValues(alpha: 0.3)),
              ),
              child: Text(
                _badgeText,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: _badgeColor,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  pack.isSubscription
                      ? Icons.workspace_premium_outlined
                      : Icons.bolt_rounded,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _packTitle,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (isBest)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0E7FF),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Лучшая цена',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1D4ED8),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _marketingNote,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${pack.totalQarmet} Qarmet (${pack.baseQarmet} + бонус ${pack.bonusQarmet})',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 2),
            Text(
              '${pack.priceKzt} KZT • ${pack.pricePerQarmet.toStringAsFixed(2)} KZT/Qarmet',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (pack.isSubscription) ...[
              const SizedBox(height: 6),
              Text(
                'Ежемесячно: +20 + 5 Qarmet, галочка профиля и премиум-привилегии.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: loading ? null : onBuy,
                child: Text(
                  pack.isSubscription
                      ? 'Подключить подписку'
                      : 'Купить за ${pack.priceKzt} KZT',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
