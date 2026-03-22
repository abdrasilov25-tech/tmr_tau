import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/exceptions/monetization_exception.dart';
import '../../domain/entities/product_entity.dart';
import '../../domain/entities/product_promotion_kind.dart';
import '../../domain/entities/promotion_order_status.dart';
import '../../domain/repositories/product_monetization_repository.dart';

/// Тарифы (₸) — можно вынести в Remote Config / Edge Function позже.
class _PromotionPricing {
  static const int top = 490;
  static const int urgent = 390;
  static const int highlight = 590;
  static const int stats = 290;
  static const int durationHours = 24;
}

/// **Платёж:** открывает URL Stripe / Halyk / Caspipay; после оплаты пользователь жмёт «Проверить оплату».
/// **Флаги в БД** выставляет webhook (Stripe) или провайдер — см. `supabase/functions/`.
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
  /// Скелетон / спиннер на время сетевого вызова createCheckoutSession.
  bool _paying = false;

  /// После открытия оплаты — id заказа для polling статуса.
  String? _pendingOrderId;

  /// Future статуса создаётся **один раз** на нажатие «Проверить» — не в build().
  Future<PromotionOrderStatus>? _statusFuture;

  Future<void> _pay(ProductPromotionKind kind) async {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Войдите, чтобы оплатить продвижение')),
      );
      return;
    }
    if (auth.user.id != widget.product.sellerId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Только владелец объявления может оплатить')),
      );
      return;
    }

    setState(() => _paying = true);
    try {
      final repo = context.read<ProductMonetizationRepository>();
      final session = await repo.createCheckoutSession(
        productId: widget.product.id,
        kind: kind,
      );
      _pendingOrderId = session.orderId;
      final uri = Uri.parse(session.checkoutUrl);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть страницу оплаты')),
        );
      }
    } on MonetizationException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  void _startVerify() {
    final id = _pendingOrderId;
    if (id == null) return;
    setState(() {
      _statusFuture = context.read<ProductMonetizationRepository>().getOrderStatus(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final isOwner = auth is AuthAuthenticated && auth.user.id == widget.product.sellerId;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Material(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          color: Theme.of(context).colorScheme.surface,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      'Продвижение объявления',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Срок по умолчанию: ${_PromotionPricing.durationHours} ч. Оплата через защищённую страницу провайдера (Stripe / банк).',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                    const SizedBox(height: 16),
                    if (!isOwner)
                      const Text('Войдите как владелец объявления.')
                    else
                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          children: [
                            _tile(
                              context,
                              title: 'В топ',
                              subtitle: '${_PromotionPricing.top} ₸',
                              kind: ProductPromotionKind.top,
                              enabled: !_paying,
                            ),
                            _tile(
                              context,
                              title: 'Срочно',
                              subtitle: '${_PromotionPricing.urgent} ₸',
                              kind: ProductPromotionKind.urgent,
                              enabled: !_paying,
                            ),
                            _tile(
                              context,
                              title: 'Выделить цветом / рамкой',
                              subtitle: '${_PromotionPricing.highlight} ₸',
                              kind: ProductPromotionKind.highlight,
                              enabled: !_paying,
                            ),
                            _tile(
                              context,
                              title: 'Статистика просмотров',
                              subtitle: '${_PromotionPricing.stats} ₸',
                              kind: ProductPromotionKind.stats,
                              enabled: !_paying,
                            ),
                            if (_pendingOrderId != null) ...[
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: _paying ? null : _startVerify,
                                child: const Text('Проверить оплату'),
                              ),
                              const SizedBox(height: 12),
                              if (_statusFuture != null)
                                FutureBuilder<PromotionOrderStatus>(
                                  future: _statusFuture,
                                  builder: (context, snapshot) {
                                    if (snapshot.connectionState ==
                                        ConnectionState.waiting) {
                                      return _VerificationSkeleton();
                                    }
                                    if (snapshot.hasError) {
                                      return Text(
                                        'Ошибка: ${snapshot.error}',
                                        style: const TextStyle(color: Colors.red),
                                      );
                                    }
                                    final st = snapshot.data;
                                    if (st == null) {
                                      return const SizedBox.shrink();
                                    }
                                    if (st.status ==
                                        PromotionPaymentStatus.paid) {
                                      scheduleMicrotask(() {
                                        widget.onPromotionActivated?.call();
                                        if (context.mounted) {
                                          Navigator.of(context).pop();
                                        }
                                      });
                                      return const Text(
                                        'Оплата успешна!',
                                        style: TextStyle(color: Colors.green),
                                      );
                                    }
                                    return Text(
                                      'Статус: ${st.status.name}. Если платёж прошёл, подождите webhook или проверьте позже.',
                                    );
                                  },
                                ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (_paying)
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.35),
                    child: const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 12),
                            Text(
                              'Переход к оплате…',
                              style: TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _tile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required ProductPromotionKind kind,
    required bool enabled,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.payment_rounded),
        onTap: enabled ? () => _pay(kind) : null,
      ),
    );
  }
}

/// **Скелетон** пока проверяется статус заказа (polling).
class _VerificationSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final base = Colors.grey.shade400;
    final hi = Colors.grey.shade200;
    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: hi,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 14,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 14,
            width: 200,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }
}
