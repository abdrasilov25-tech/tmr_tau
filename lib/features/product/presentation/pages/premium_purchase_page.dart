import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/services/payment_service.dart';

class PremiumPurchasePage extends StatefulWidget {
  const PremiumPurchasePage({super.key});

  @override
  State<PremiumPurchasePage> createState() => _PremiumPurchasePageState();
}

class _PremiumPurchasePageState extends State<PremiumPurchasePage> {
  bool _loading = false;

  Future<void> _buy() async {
    setState(() => _loading = true);
    final payment = context.read<PaymentService>();
    final result = await payment.purchasePremium();
    if (!mounted) return;
    setState(() => _loading = false);
    final text = result.message ??
        (result.status == PaymentResultStatus.success
            ? 'Premium активирован'
            : 'Покупка не завершена');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Premium')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Premium открывает радиусы 10 км и 20 км.'),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _loading ? null : _buy,
              child: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Купить premium_subscription'),
            ),
          ],
        ),
      ),
    );
  }
}
