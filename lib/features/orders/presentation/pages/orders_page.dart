import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/router/go_router_pop_safe.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/order_entity.dart';
import '../../domain/repositories/orders_repository.dart';

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  late Future<List<OrderEntity>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<OrderEntity>> _load() async {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated) return const <OrderEntity>[];
    return context.read<OrdersRepository>().getMyOrders(auth.user.id);
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    await next;
  }

  Future<void> _acceptBySeller(OrderEntity order) async {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated) return;
    await context.read<OrdersRepository>().acceptOrderBySeller(
          orderId: order.id,
          sellerId: auth.user.id,
        );
    await _refresh();
  }

  Future<void> _confirmByBuyer(OrderEntity order) async {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated) return;
    await context.read<OrdersRepository>().confirmReceiptByBuyer(
          orderId: order.id,
          buyerId: auth.user.id,
        );
    await _refresh();
  }

  Future<void> _cancel(OrderEntity order) async {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated) return;
    await context.read<OrdersRepository>().cancelOrder(
          orderId: order.id,
          actorId: auth.user.id,
        );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final currentUserId = auth is AuthAuthenticated ? auth.user.id : '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Мои заказы'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.popOrGoHomeFeed(),
        ),
      ),
      body: FutureBuilder<List<OrderEntity>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data ?? const <OrderEntity>[];
          if (list.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 80,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Безопасных сделок пока нет',
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              separatorBuilder: (_, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final order = list[index];
                final isBuyer = order.buyerId == currentUserId;
                return _OrderCard(
                  order: order,
                  isBuyer: isBuyer,
                  onAcceptBySeller:
                      (order.status == OrderStatus.pendingSeller && !isBuyer)
                          ? () => _acceptBySeller(order)
                          : null,
                  onConfirmByBuyer:
                      (order.status == OrderStatus.inEscrow && isBuyer)
                          ? () => _confirmByBuyer(order)
                          : null,
                  onCancel: !order.isTerminal ? () => _cancel(order) : null,
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.isBuyer,
    this.onAcceptBySeller,
    this.onConfirmByBuyer,
    this.onCancel,
  });

  final OrderEntity order;
  final bool isBuyer;
  final VoidCallback? onAcceptBySeller;
  final VoidCallback? onConfirmByBuyer;
  final VoidCallback? onCancel;

  String get _statusLabel {
    switch (order.status) {
      case OrderStatus.pendingSeller:
        return 'Ожидает подтверждения продавца';
      case OrderStatus.inEscrow:
        return 'В безопасной сделке (escrow)';
      case OrderStatus.completed:
        return 'Завершено';
      case OrderStatus.cancelled:
        return 'Отменено';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              order.productTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(_statusLabel),
            const SizedBox(height: 6),
            Text(
              'Сумма: ${order.amountKzt.toStringAsFixed(0)} ₸ · '
              'Комиссия: ${order.commissionPercent}% '
              '(${order.commissionKzt.toStringAsFixed(0)} ₸)',
            ),
            if (!isBuyer)
              Text('К выплате продавцу: ${order.sellerAmountKzt.toStringAsFixed(0)} ₸'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onAcceptBySeller != null)
                  FilledButton(
                    onPressed: onAcceptBySeller,
                    child: const Text('Принять сделку'),
                  ),
                if (onConfirmByBuyer != null)
                  FilledButton(
                    onPressed: onConfirmByBuyer,
                    child: const Text('Подтвердить получение'),
                  ),
                if (onCancel != null)
                  OutlinedButton(
                    onPressed: onCancel,
                    child: const Text('Отменить'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
