import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/go_router_pop_safe.dart';
import '../../../../core/widgets/cached_product_image.dart';
import '../../domain/entities/cart_item_entity.dart';

class CartPage extends StatelessWidget {
  const CartPage({super.key, this.items = const []});

  final List<CartItemEntity> items;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Корзина'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.popOrGoHomeFeed(),
        ),
      ),
      body: items.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.shopping_cart_outlined,
                    size: 80,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Корзина пуста',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Добавляйте товары кнопкой «В корзину» на странице товара',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length + 1,
              itemBuilder: (context, index) {
                if (index == items.length) {
                  final total = items.fold<double>(
                    0, (s, e) => s + e.total);
                  return Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: FilledButton(
                      onPressed: () => context.push('/orders'),
                      child: Text(
                      'Оформить заказ • ${total.toStringAsFixed(0)} ₸'),
                    ),
                  );
                }
                final item = items[index];
                return _CartTile(item: item);
              },
            ),
    );
  }
}

class _CartTile extends StatelessWidget {
  const _CartTile({required this.item});

  final CartItemEntity item;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(8),
        leading: SizedBox(
          width: 72,
          height: 72,
          child: CachedProductImage(
            imageUrl: item.product.imageUrl,
            width: 72,
            height: 72,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        title: Text(item.product.title),
        subtitle: Text('${item.product.priceFormatted} × ${item.quantity}'),
        trailing: Text(
          '${(item.product.price * item.quantity).toStringAsFixed(0)} ₸',
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
    );
  }
}
