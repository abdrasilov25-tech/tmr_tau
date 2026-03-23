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
    final isOwner = auth is AuthAuthenticated && auth.user.id == product.sellerId;

    return BlocProvider(
      create: (_) => PaymentCubit(context.read<PaymentService>())..initStore(),
      child: BlocConsumer<PaymentCubit, PaymentUiState>(
        listener: (context, state) {
          if (state.status == PaymentUiStatus.success) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Покупка успешно завершена')),
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
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                        'Продвижение и Premium',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      if (!isOwner)
                        const Text('Войдите как владелец объявления.')
                      else ...[
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.bolt),
                            title: const Text('Boost товара'),
                            subtitle: const Text('Разовая покупка: boost_post'),
                            onTap: loading
                                ? null
                                : () => context.read<PaymentCubit>().buyBoost(product.id),
                          ),
                        ),
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.workspace_premium_outlined),
                            title: const Text('Premium подписка'),
                            subtitle: const Text('Подписка: premium_subscription'),
                            onTap: loading
                                ? null
                                : () => context.read<PaymentCubit>().buyPremium(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: loading
                              ? null
                              : () => context.read<PaymentCubit>().restorePurchases(),
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
