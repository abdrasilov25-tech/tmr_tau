import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../../core/widgets/cached_product_image.dart';
import '../../domain/entities/cart_item_entity.dart';
import '../cart_notifier.dart';

class CartPage extends StatelessWidget {
  const CartPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartNotifier>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Корзина'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: cart.items.isEmpty
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
              itemCount: cart.items.length + 1,
              itemBuilder: (context, index) {
                if (index == cart.items.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: FilledButton(
                      onPressed: () => context.push('/orders'),
                      child: Text(
                          'Оформить заказ • ${cart.total.toStringAsFixed(0)} ₸'),
                    ),
                  );
                }
                final item = cart.items[index];
                return _CartTile(
                  item: item,
                  onRemove: () =>
                      context.read<CartNotifier>().removeItem(item.product.id),
                );
              },
            ),
    );
  }
}

class _CartTile extends StatelessWidget {
  const _CartTile({required this.item, required this.onRemove});

  final CartItemEntity item;
  final VoidCallback onRemove;

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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${(item.product.price * item.quantity).toStringAsFixed(0)} ₸',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              color: Theme.of(context).colorScheme.error,
              tooltip: 'Убрать из корзины',
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}
