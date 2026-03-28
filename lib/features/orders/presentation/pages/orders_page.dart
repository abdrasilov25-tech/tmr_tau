import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/widgets/cached_product_image.dart';
import '../../data/repositories/mock_orders_repository.dart';
import '../../domain/entities/order_entity.dart';
import '../../domain/repositories/orders_repository.dart';

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  final OrdersRepository _repository = MockOrdersRepository();

  late Future<List<OrderEntity>> _ordersFuture;

  @override
  void initState() {
    super.initState();
    _ordersFuture = _repository.getOrders();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Мои заказы'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: FutureBuilder<List<OrderEntity>>(
        future: _ordersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Ошибка загрузки заказов',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            );
          }
          final orders = snapshot.data ?? [];
          if (orders.isEmpty) {
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
                    'Здесь появятся ваши заказы',
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: orders.length,
            itemBuilder: (context, index) =>
                _OrderTile(order: orders[index]),
          );
        },
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order});

  final OrderEntity order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CachedProductImage(
              imageUrl: order.productImageUrl,
              width: 72,
              height: 72,
              borderRadius: BorderRadius.circular(8),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.productTitle,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${order.total.toStringAsFixed(0)} ₸ · ${order.quantity} шт.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  _StatusChip(status: order.status),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final OrderStatus status;

  Color _bgColor(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    switch (status) {
      case OrderStatus.pending:
        return cs.surfaceContainerHighest;
      case OrderStatus.confirmed:
        return cs.primaryContainer;
      case OrderStatus.shipped:
        return cs.secondaryContainer;
      case OrderStatus.delivered:
        return cs.tertiaryContainer;
      case OrderStatus.cancelled:
        return cs.errorContainer;
    }
  }

  Color _fgColor(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    switch (status) {
      case OrderStatus.pending:
        return cs.onSurfaceVariant;
      case OrderStatus.confirmed:
        return cs.onPrimaryContainer;
      case OrderStatus.shipped:
        return cs.onSecondaryContainer;
      case OrderStatus.delivered:
        return cs.onTertiaryContainer;
      case OrderStatus.cancelled:
        return cs.onErrorContainer;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _bgColor(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: _fgColor(context)),
      ),
    );
  }
}
