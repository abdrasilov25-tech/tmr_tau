import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/supabase_constants.dart';
import '../../domain/entities/battle_history_entry.dart';
import '../../domain/entities/donator_score.dart';
import '../../domain/entities/gift.dart';
import '../../domain/entities/live_battle.dart';
import '../../domain/entities/wallet.dart';
import '../../domain/repositories/live_battle_repository.dart';

class LiveBattleRepositoryImpl implements LiveBattleRepository {
  LiveBattleRepositoryImpl(this._client);

  final SupabaseClient _client;

  @override
  Future<LiveBattle> startBattle(String userA, String userB) async {
    final id = await _client.rpc<String>(
      'start_live_battle',
      params: <String, dynamic>{
        'p_host_a': userA,
        'p_host_b': userB,
      },
    );
    final row = await _client
        .from(SupabaseConstants.liveBattlesTable)
        .select()
        .eq('id', id)
        .single();
    return _mapBattle(Map<String, dynamic>.from(row as Map));
  }

  @override
  Future<void> sendLike({
    required String battleId,
    required String userId,
    required String targetHost,
  }) async {
    await _client.rpc<void>(
      'send_live_battle_like',
      params: <String, dynamic>{
        'p_battle_id': battleId,
        'p_target_host': targetHost,
      },
    );
  }

  @override
  Future<void> sendGift({
    required String battleId,
    required String giftId,
    required String senderId,
    required String targetHost,
  }) async {
    await _client.rpc<void>(
      'send_live_battle_gift',
      params: <String, dynamic>{
        'p_battle_id': battleId,
        'p_gift_id': giftId,
        'p_target_host': targetHost,
      },
    );
  }

  @override
  Future<int> getBalance(String userId) async {
    final row = await _client
        .from(SupabaseConstants.usersTable)
        .select('qarmet_balance')
        .eq('id', userId)
        .maybeSingle();
    return (row?['qarmet_balance'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<int> addQarmet(String userId, int amount) async {
    final next = await _client.rpc<int>(
      'credit_qarmet',
      params: <String, dynamic>{
        'p_amount': amount,
        'p_reason': 'live_battle_topup',
      },
    );
    return next;
  }

  @override
  Future<int> deductQarmet(String userId, int amount) async {
    final next = await _client.rpc<int>(
      'spend_qarmet',
      params: <String, dynamic>{
        'p_amount': amount,
        'p_reason': 'live_battle_manual_spend',
      },
    );
    return next;
  }

  @override
  Future<Wallet> getWallet(String userId) async {
    return Wallet(userId: userId, balance: await getBalance(userId));
  }

  @override
  Future<List<Gift>> getGifts() async {
    final rows = await _client
        .from(SupabaseConstants.giftCatalogTable)
        .select()
        .order('price', ascending: true);
    return (rows as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .map(
          (e) => Gift(
            id: (e['id'] ?? '').toString(),
            name: (e['name'] ?? '').toString(),
            price: (e['price'] as num?)?.toInt() ?? 0,
            animation: (e['animation'] ?? '').toString(),
          ),
        )
        .toList(growable: false);
  }

  @override
  Stream<LiveBattle> watchBattle(String battleId) {
    return _client
        .from(SupabaseConstants.liveBattlesTable)
        .stream(primaryKey: ['id'])
        .eq('id', battleId)
        .map((rows) => rows.isEmpty ? null : rows.first)
        .where((e) => e != null)
        .map((e) => _mapBattle(Map<String, dynamic>.from(e!)));
  }

  @override
  Stream<List<DonatorScore>> watchTopDonators(String battleId) {
    return _client
        .from(SupabaseConstants.liveBattleEventsTable)
        .stream(primaryKey: ['id'])
        .eq('battle_id', battleId)
        .order('created_at', ascending: false)
        .map((rows) {
          final bySender = <String, int>{};
          for (final raw in rows) {
            final row = Map<String, dynamic>.from(raw);
            if ((row['event_type'] ?? '') != 'gift') continue;
            final sender = (row['sender_id'] ?? '').toString();
            if (sender.isEmpty) continue;
            final amount = (row['gift_price'] as num?)?.toInt() ?? 0;
            bySender.update(sender, (v) => v + amount, ifAbsent: () => amount);
          }
          final top = bySender.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          return top
              .take(3)
              .map((e) => DonatorScore(userId: e.key, amount: e.value))
              .toList(growable: false);
        });
  }

  @override
  Future<List<BattleHistoryEntry>> getBattleHistory(String userId) async {
    final rows = await _client
        .from(SupabaseConstants.liveBattleResultsTable)
        .select()
        .or('host_a.eq.$userId,host_b.eq.$userId')
        .order('created_at', ascending: false)
        .limit(30);
    return (rows as List<dynamic>).map((raw) {
      final row = Map<String, dynamic>.from(raw as Map);
      return BattleHistoryEntry(
        battleId: (row['battle_id'] ?? '').toString(),
        winnerId: row['winner_id'] as String?,
        scoreA: (row['score_a'] as num?)?.toInt() ?? 0,
        scoreB: (row['score_b'] as num?)?.toInt() ?? 0,
        maybeMvpSenderId: row['mvp_sender_id'] as String?,
        createdAt:
            DateTime.tryParse((row['created_at'] ?? '').toString()) ??
            DateTime.now().toUtc(),
      );
    }).toList(growable: false);
  }

  @override
  Future<void> finishBattle(String battleId) async {
    await _client.rpc<void>(
      'finalize_live_battle',
      params: <String, dynamic>{'p_battle_id': battleId},
    );
  }

  LiveBattle _mapBattle(Map<String, dynamic> row) {
    return LiveBattle(
      id: (row['id'] ?? '').toString(),
      hostA: (row['host_a'] ?? '').toString(),
      hostB: (row['host_b'] ?? '').toString(),
      scoreA: (row['score_a'] as num?)?.toInt() ?? 0,
      scoreB: (row['score_b'] as num?)?.toInt() ?? 0,
      endTime:
          DateTime.tryParse((row['end_time'] ?? '').toString()) ??
          DateTime.now().toUtc(),
      isActive: row['is_active'] == true,
    );
  }
}
