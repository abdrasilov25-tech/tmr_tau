import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../data/services/payment_service.dart';
import '../../domain/entities/product_entity.dart';
import '../bloc/payment_cubit.dart';

class ProductPromotionSheet extends StatelessWidget {
  const ProductPromotionSheet({
    super.key,
    required this.product,
    this.onPromotionActivated,
  });

  final ProductEntity product;
  final VoidCallback? onPromotionActivated;

  static Future<void> show(
    BuildContext context, {
    required ProductEntity product,
    VoidCallback? onPromotionActivated,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ProductPromotionSheet(
        product: product,
        onPromotionActivated: onPromotionActivated,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final isOwner =
        auth is AuthAuthenticated && auth.user.id == product.sellerId;

    return BlocProvider(
      create: (_) => PaymentCubit(context.read<PaymentService>())..initStore(),
      child: BlocConsumer<PaymentCubit, PaymentUiState>(
        listener: (context, state) {
          if (state.status == PaymentUiStatus.success) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Операция с Qarmet выполнена')),
            );
            onPromotionActivated?.call();
          } else if (state.status == PaymentUiStatus.error ||
              state.status == PaymentUiStatus.cancelled) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message ?? 'Операция не выполнена')),
            );
          }
        },
        builder: (context, state) {
          final loading = state.status == PaymentUiStatus.loading;
          return DraggableScrollableSheet(
            initialChildSize: 0.55,
            minChildSize: 0.35,
            maxChildSize: 0.9,
            expand: false,
            builder: (context, scrollController) {
              return Material(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                color: Theme.of(context).colorScheme.surface,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  child: ListView(
                    controller: scrollController,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade400,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Qarmet: продвижение и профиль',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      if (!isOwner)
                        const Text('Войдите как владелец объявления.')
                      else ...[
                        Card(
                          child: ListTile(
                            leading: const Icon(
                              Icons.account_balance_wallet_outlined,
                            ),
                            title: Text('Баланс Qarmet: ${state.balance}'),
                            subtitle: Text(
                              state.isOfficialPageActive
                                  ? 'official_page активна: ежемесячные начисления включены'
                                  : 'Подписка official_page не активна',
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.refresh),
                              onPressed: loading
                                  ? null
                                  : () => context
                                        .read<PaymentCubit>()
                                        .refreshWallet(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Пакеты в магазине',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        ...state.catalog.map(
                          (pack) => Card(
                            child: ListTile(
                              leading: Icon(
                                pack.isSubscription
                                    ? Icons.autorenew
                                    : Icons.shopping_cart_checkout,
                              ),
                              title: Text(
                                '${pack.productId}: ${pack.baseQarmet}+${pack.bonusQarmet} Qarmet',
                              ),
                              subtitle: Text(
                                '${pack.priceKzt} KZT, ~${pack.pricePerQarmet.toStringAsFixed(2)} KZT/Qarmet',
                              ),
                              onTap: loading
                                  ? null
                                  : () => context
                                        .read<PaymentCubit>()
                                        .buyQarmetPackage(pack.productId),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Продвижение товара (каждое = 1 Qarmet)',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.north_rounded),
                            title: const Text('В топ на +24 часа'),
                            subtitle: const Text('Стоимость: 1 Qarmet'),
                            onTap: loading
                                ? null
                                : () => context
                                      .read<PaymentCubit>()
                                      .spendTopPromotion(product.id),
                          ),
                        ),
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.priority_high),
                            title: const Text('Срочно на +24 часа'),
                            subtitle: const Text('Стоимость: 1 Qarmet'),
                            onTap: loading
                                ? null
                                : () => context
                                      .read<PaymentCubit>()
                                      .spendUrgentPromotion(product.id),
                          ),
                        ),
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.auto_awesome),
                            title: const Text('Выделение на +24 часа'),
                            subtitle: const Text('Стоимость: 1 Qarmet'),
                            onTap: loading
                                ? null
                                : () => context
                                      .read<PaymentCubit>()
                                      .spendHighlightPromotion(product.id),
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: loading
                              ? null
                              : () => context
                                    .read<PaymentCubit>()
                                    .restorePurchases(),
                          icon: const Icon(Icons.restore),
                          label: const Text('Восстановить покупки'),
                        ),
                      ],
                      if (loading) ...[
                        const SizedBox(height: 12),
                        const Center(child: CircularProgressIndicator()),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
