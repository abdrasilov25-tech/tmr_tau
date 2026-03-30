import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/services/payment_service.dart';
import '../../domain/entities/qarmet_promotion_history_item.dart';
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
          actions: [
            Builder(
              builder: (ctx) {
                return IconButton(
                  tooltip: 'Обновить',
                  onPressed: () => ctx.read<PaymentCubit>().refreshWallet(),
                  icon: const Icon(Icons.refresh_rounded),
                );
              },
            ),
          ],
        ),
        body: BlocConsumer<PaymentCubit, PaymentUiState>(
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
            return RefreshIndicator(
              onRefresh: () => context.read<PaymentCubit>().refreshWallet(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _BalanceCard(state: state),
                  const SizedBox(height: 14),
                  Text(
                    'Пополнить Qarmet',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  ...state.catalog.map(
                    (pack) => Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      child: ListTile(
                        leading: Icon(
                          pack.isSubscription
                              ? Icons.autorenew_rounded
                              : Icons.shopping_bag_outlined,
                        ),
                        title: Text(
                          '${pack.productId}: ${pack.baseQarmet}+${pack.bonusQarmet} Qarmet',
                        ),
                        subtitle: Text(
                          '${pack.priceKzt} KZT · ${pack.pricePerQarmet.toStringAsFixed(2)} KZT/Qarmet',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: loading
                            ? null
                            : () => context
                                  .read<PaymentCubit>()
                                  .buyQarmetPackage(pack.productId),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Продвижение товаров: 1 Qarmet',
                    style: Theme.of(context).textTheme.titleMedium,
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
  const _BalanceCard({required this.state});

  final PaymentUiState state;

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
        ],
      ),
    );
  }
}
