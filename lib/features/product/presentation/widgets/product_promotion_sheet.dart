import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../data/services/payment_service.dart';
import '../../domain/entities/product_entity.dart';
import '../../domain/entities/qarmet_product.dart';
import '../bloc/payment_cubit.dart';

class ProductPromotionSheet extends StatefulWidget {
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
  State<ProductPromotionSheet> createState() => _ProductPromotionSheetState();
}

class _ProductPromotionSheetState extends State<ProductPromotionSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<PaymentCubit>().initStore();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isOwner = context.select<AuthBloc, bool>(
      (bloc) {
        final s = bloc.state;
        return s is AuthAuthenticated && s.user.id == widget.product.sellerId;
      },
    );

    return BlocConsumer<PaymentCubit, PaymentUiState>(
        listener: (context, state) {
          if (state.status == PaymentUiStatus.success) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Операция с Qarmet выполнена')),
            );
            widget.onPromotionActivated?.call();
          } else if (state.status == PaymentUiStatus.error ||
              state.status == PaymentUiStatus.cancelled) {
            final message = state.message ?? 'Операция не выполнена';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(message)),
            );
            if (_isInsufficientQarmetMessage(message)) {
              Navigator.of(context).pop();
              context.push('/qarmet-wallet');
            }
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
                              onPressed: state.isWalletWideBusy
                                  ? null
                                  : () => context.read<PaymentCubit>().refreshWallet(
                                        forceRefresh: true,
                                      ),
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
                                '${_packTitle(pack)} · ${pack.totalQarmet} Qarmet',
                              ),
                              subtitle: Text(
                                '${pack.priceKzt} тг, ~${pack.pricePerQarmet.toStringAsFixed(2)} тг/Qarmet',
                              ),
                              onTap: state.canTapBuyQarmetPackage(pack.productId)
                                  ? () => context
                                      .read<PaymentCubit>()
                                      .buyQarmetPackage(pack.productId)
                                  : null,
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
                                      .spendTopPromotion(widget.product.id),
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
                                      .spendUrgentPromotion(widget.product.id),
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
                                      .spendHighlightPromotion(widget.product.id),
                          ),
                        ),
                        Card(
                          color: Colors.indigo.shade50,
                          child: ListTile(
                            leading: const Icon(Icons.all_inclusive_rounded),
                            title: const Text('Пакет "Все и сразу" на +24 часа'),
                            subtitle: const Text(
                              'Топ + Срочно + Выделение за 2 Qarmet',
                            ),
                            onTap: loading
                                ? null
                                : () => context
                                      .read<PaymentCubit>()
                                      .spendAllInOnePromotion(widget.product.id),
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
    );
  }
}

bool _isInsufficientQarmetMessage(String message) {
  final text = message.toLowerCase();
  return text.contains('недостаточно qarmet') ||
      (text.contains('нужно:') && text.contains('доступно:'));
}

String _packTitle(QarmetProduct pack) {
  switch (pack.productId) {
    case PaymentService.promotionStartProductId:
      return 'Start пакет';
    case PaymentService.promotionPremiumProductId:
      return 'Premium пакет';
    case PaymentService.promotionBusinessProductId:
      return 'Business пакет';
    case PaymentService.officialPageProductId:
      return 'Official Page';
    default:
      return pack.title;
  }
}
