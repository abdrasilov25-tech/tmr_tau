import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../data/services/payment_service.dart';

/// Покупка IAP Premium для расширенных радиусов в новостях «Рядом».
class PremiumPurchasePage extends StatefulWidget {
  const PremiumPurchasePage({super.key});

  @override
  State<PremiumPurchasePage> createState() => _PremiumPurchasePageState();
}

class _PremiumPurchasePageState extends State<PremiumPurchasePage> {
  bool _bootstrapping = true;
  bool _buying = false;
  bool _alreadyPremium = false;
  DateTime? _premiumUntil;
  String? _storeError;
  String? _priceFromStore;
  String? _titleFromStore;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final payment = context.read<PaymentService>();
    try {
      await Future.wait<void>([
        payment.initStore(),
        _refreshPremiumRow(payment),
      ]);
    } catch (_) {
      // initStore / сеть — показываем экран с текстом ошибки из payment.storeInitError
    }
    if (!mounted) return;
    setState(() {
      _bootstrapping = false;
      _storeError = payment.storeInitError;
      _priceFromStore = payment.storeKitPriceForProduct(
        PaymentService.premiumSubscriptionProductId,
      );
      _titleFromStore = payment.storeKitTitleForProduct(
        PaymentService.premiumSubscriptionProductId,
      );
    });
  }

  Future<void> _refreshPremiumRow(PaymentService payment) async {
    final info = await payment.getNewsMapPremiumInfo();
    if (!mounted) return;
    setState(() {
      _alreadyPremium = info.active;
      _premiumUntil = info.until;
    });
  }

  Future<void> _buy() async {
    final payment = context.read<PaymentService>();
    if (!payment.isStoreCatalogLoaded && payment.storeInitError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            payment.storeInitError ?? 'Магазин недоступен',
          ),
        ),
      );
      return;
    }
    if (!payment.isStoreCatalogLoaded) {
      await payment.initStore(forceCatalogRefresh: true);
      if (!mounted) return;
      setState(() {
        _storeError = payment.storeInitError;
        _priceFromStore = payment.storeKitPriceForProduct(
          PaymentService.premiumSubscriptionProductId,
        );
        _titleFromStore = payment.storeKitTitleForProduct(
          PaymentService.premiumSubscriptionProductId,
        );
      });
      if (!payment.isStoreCatalogLoaded) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось подключиться к App Store. Попробуйте позже.'),
          ),
        );
        return;
      }
    }

    setState(() => _buying = true);
    await Future<void>.delayed(Duration.zero);

    final result = await payment.purchasePremium();

    if (!mounted) return;
    setState(() => _buying = false);

    switch (result.status) {
      case PaymentResultStatus.success:
        await _refreshPremiumRow(payment);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Premium активирован')),
        );
        context.pop(true);
      case PaymentResultStatus.cancelled:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message ?? 'Покупка отменена'),
          ),
        );
      case PaymentResultStatus.error:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message ?? 'Ошибка оплаты'),
          ),
        );
    }
  }

  String _untilLabel(DateTime utc) {
    final local = utc.toLocal();
    final d =
        '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')}.${local.year}';
    return d;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final buttonLabel = _priceFromStore != null && _priceFromStore!.isNotEmpty
        ? 'Оформить Premium · $_priceFromStore'
        : 'Оформить Premium';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Premium для «Рядом»'),
      ),
      body: _bootstrapping
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.radar_rounded,
                    size: 56,
                    color: scheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Расширенные радиусы',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Бесплатно — поиск постов в радиусе 5 км. '
                    'С Premium доступны 10 км и 20 км.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          height: 1.45,
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  if (_titleFromStore != null &&
                      _titleFromStore!.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      _titleFromStore!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (_alreadyPremium)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: scheme.primary.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.verified_rounded, color: scheme.primary),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Premium уже активен',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ),
                            ],
                          ),
                          if (_premiumUntil != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Действует до ${_untilLabel(_premiumUntil!)}',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ] else ...[
                            const SizedBox(height: 8),
                            Text(
                              'Доступны радиусы 10 и 20 км.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ],
                      ),
                    )
                  else ...[
                    if (_storeError != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _storeError!,
                          style: TextStyle(color: scheme.onErrorContainer),
                        ),
                      ),
                    FilledButton(
                      onPressed: (_buying) ? null : _buy,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _buying
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              buttonLabel,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Text(
                    'Оплата проходит через App Store. После покупки вернитесь в «Рядом» — '
                    'радиусы обновятся автоматически.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                  ),
                ],
              ),
            ),
    );
  }
}
