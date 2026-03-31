import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/supabase_constants.dart';
import '../../domain/entities/order_entity.dart';
import '../../domain/repositories/orders_repository.dart';

class OrdersRepositoryImpl implements OrdersRepository {
  OrdersRepositoryImpl(this._client);

  final SupabaseClient _client;

  @override
  Future<OrderEntity> createSafeOrder({
    required String buyerId,
    required String sellerId,
    required String productId,
    required String productTitle,
    required double amountKzt,
    int commissionPercent = 4,
  }) async {
    if (buyerId == sellerId) {
      throw Exception('Нельзя создать сделку со своим товаром');
    }
    if (amountKzt <= 0) {
      throw Exception('Сумма сделки должна быть больше 0');
    }
    final commission = (amountKzt * commissionPercent) / 100.0;
    final sellerAmount = amountKzt - commission;
    final payload = <String, dynamic>{
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': productId,
      'product_title': productTitle,
      'status': 'pending_seller',
      'amount_kzt': amountKzt,
      'commission_percent': commissionPercent,
      'commission_kzt': commission,
      'seller_amount_kzt': sellerAmount,
      'safe_purchase': true,
    };
    final row = await _client
        .from(SupabaseConstants.ordersTable)
        .insert(payload)
        .select()
        .single();
    final order = _mapOrder(row);
    await _insertOrderNotification(
      userId: sellerId,
      actorId: buyerId,
      type: 'order_safe_created',
      title: 'Новая безопасная сделка',
      body:
          'Покупатель оформил безопасную сделку по товару "$productTitle". Сумма ${amountKzt.toStringAsFixed(0)} ₸, комиссия 4%.',
      productId: productId,
    );
    return order;
  }

  @override
  Future<List<OrderEntity>> getMyOrders(String userId) async {
    final rows = await _client
        .from(SupabaseConstants.ordersTable)
        .select()
        .or('buyer_id.eq.$userId,seller_id.eq.$userId')
        .order('created_at', ascending: false);
    return (rows as List<dynamic>)
        .map((e) => _mapOrder(Map<String, dynamic>.from(e as Map)))
        .toList(growable: false);
  }

  @override
  Future<void> acceptOrderBySeller({
    required String orderId,
    required String sellerId,
  }) async {
    final row = await _client
        .from(SupabaseConstants.ordersTable)
        .select('buyer_id, product_id, product_title, amount_kzt')
        .eq('id', orderId)
        .eq('seller_id', sellerId)
        .eq('status', 'pending_seller')
        .maybeSingle();
    if (row == null) return;
    final now = DateTime.now().toUtc().toIso8601String();
    await _client
        .from(SupabaseConstants.ordersTable)
        .update({
          'status': 'in_escrow',
          'seller_accepted_at': now,
          'updated_at': now,
        })
        .eq('id', orderId)
        .eq('seller_id', sellerId)
        .eq('status', 'pending_seller');
    await _insertOrderNotification(
      userId: (row['buyer_id'] ?? '').toString(),
      actorId: sellerId,
      type: 'order_safe_accepted',
      title: 'Продавец принял сделку',
      body:
          'Продавец подтвердил безопасную сделку по "${(row['product_title'] ?? 'товару')}".',
      productId: (row['product_id'] ?? '').toString(),
    );
  }

  @override
  Future<void> confirmReceiptByBuyer({
    required String orderId,
    required String buyerId,
  }) async {
    final row = await _client
        .from(SupabaseConstants.ordersTable)
        .select('seller_id, product_id, product_title')
        .eq('id', orderId)
        .eq('buyer_id', buyerId)
        .eq('status', 'in_escrow')
        .maybeSingle();
    if (row == null) return;
    final now = DateTime.now().toUtc().toIso8601String();
    await _client
        .from(SupabaseConstants.ordersTable)
        .update({
          'status': 'completed',
          'buyer_confirmed_at': now,
          'completed_at': now,
          'updated_at': now,
        })
        .eq('id', orderId)
        .eq('buyer_id', buyerId)
        .eq('status', 'in_escrow');
    await _insertOrderNotification(
      userId: (row['seller_id'] ?? '').toString(),
      actorId: buyerId,
      type: 'order_safe_completed',
      title: 'Сделка завершена',
      body:
          'Покупатель подтвердил получение по сделке "${(row['product_title'] ?? 'товар')}".',
      productId: (row['product_id'] ?? '').toString(),
    );
  }

  @override
  Future<void> cancelOrder({
    required String orderId,
    required String actorId,
  }) async {
    final row = await _client
        .from(SupabaseConstants.ordersTable)
        .select('buyer_id, seller_id, product_id, product_title, status')
        .eq('id', orderId)
        .or('buyer_id.eq.$actorId,seller_id.eq.$actorId')
        .inFilter('status', ['pending_seller', 'in_escrow'])
        .maybeSingle();
    if (row == null) return;
    final now = DateTime.now().toUtc().toIso8601String();
    await _client
        .from(SupabaseConstants.ordersTable)
        .update({
          'status': 'cancelled',
          'cancelled_at': now,
          'updated_at': now,
        })
        .eq('id', orderId)
        .or('buyer_id.eq.$actorId,seller_id.eq.$actorId')
        .inFilter('status', ['pending_seller', 'in_escrow']);
    final buyerId = (row['buyer_id'] ?? '').toString();
    final sellerId = (row['seller_id'] ?? '').toString();
    final recipient = actorId == buyerId ? sellerId : buyerId;
    await _insertOrderNotification(
      userId: recipient,
      actorId: actorId,
      type: 'order_safe_cancelled',
      title: 'Сделка отменена',
      body: 'Безопасная сделка по "${(row['product_title'] ?? 'товар')}" была отменена.',
      productId: (row['product_id'] ?? '').toString(),
    );
  }

  Future<void> _insertOrderNotification({
    required String userId,
    required String actorId,
    required String type,
    required String title,
    required String body,
    required String productId,
  }) async {
    if (userId.isEmpty || actorId.isEmpty || userId == actorId) return;
    await _client.from(SupabaseConstants.notificationsTable).insert({
      'user_id': userId,
      'actor_id': actorId,
      'type': type,
      'title': title,
      'body': body,
      'product_id': productId.isEmpty ? null : productId,
    });
  }

  OrderEntity _mapOrder(Map<String, dynamic> row) {
    final statusRaw = (row['status'] as String? ?? 'pending_seller').trim();
    final status = switch (statusRaw) {
      'pending_seller' => OrderStatus.pendingSeller,
      'in_escrow' => OrderStatus.inEscrow,
      'completed' => OrderStatus.completed,
      'cancelled' => OrderStatus.cancelled,
      _ => OrderStatus.pendingSeller,
    };
    DateTime? parse(String key) => DateTime.tryParse((row[key] ?? '').toString());
    return OrderEntity(
      id: (row['id'] ?? '').toString(),
      buyerId: (row['buyer_id'] ?? '').toString(),
      sellerId: (row['seller_id'] ?? '').toString(),
      productId: (row['product_id'] ?? '').toString(),
      productTitle: (row['product_title'] as String?) ?? 'Товар',
      status: status,
      amountKzt: ((row['amount_kzt'] as num?) ?? 0).toDouble(),
      commissionPercent: (row['commission_percent'] as int?) ?? 4,
      commissionKzt: ((row['commission_kzt'] as num?) ?? 0).toDouble(),
      sellerAmountKzt: ((row['seller_amount_kzt'] as num?) ?? 0).toDouble(),
      createdAt: parse('created_at') ?? DateTime.now(),
      sellerAcceptedAt: parse('seller_accepted_at'),
      buyerConfirmedAt: parse('buyer_confirmed_at'),
      completedAt: parse('completed_at'),
      cancelledAt: parse('cancelled_at'),
    );
  }
}
