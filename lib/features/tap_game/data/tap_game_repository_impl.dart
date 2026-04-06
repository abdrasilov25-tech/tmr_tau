import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/supabase_constants.dart';
import '../domain/entities/tap_game_leaderboard_entry.dart';
import '../domain/entities/tap_game_play_state.dart';
import '../domain/entities/tap_game_session_info.dart';
import '../domain/repositories/tap_game_repository.dart';

class TapGameRepositoryImpl implements TapGameRepository {
  TapGameRepositoryImpl(this._client);

  final SupabaseClient _client;

  @override
  Future<String> getOrCreateSessionId() async {
    final id = await _client.rpc<String>('tap_game_get_or_create_session');
    if (id.isEmpty) {
      throw Exception('tap_game: empty session id');
    }
    return id;
  }

  @override
  Future<TapGameSessionInfo?> fetchSession(String sessionId) async {
    final row = await _client
        .from(SupabaseConstants.tapGameSessionsTable)
        .select('id, started_at, ends_at, is_active')
        .eq('id', sessionId)
        .maybeSingle();
    if (row == null) return null;
    final m = Map<String, dynamic>.from(row as Map);
    return TapGameSessionInfo(
      id: m['id'].toString(),
      startedAt: DateTime.parse(m['started_at'].toString()),
      endsAt: DateTime.parse(m['ends_at'].toString()),
      isActive: m['is_active'] as bool? ?? false,
    );
  }

  @override
  Future<TapGameTapResult> addScore({
    required String sessionId,
    required int delta,
  }) async {
    final raw = await _client.rpc<dynamic>(
      'tap_game_add_score',
      params: <String, dynamic>{
        'p_session_id': sessionId,
        'p_delta': delta,
      },
    );
    final m = Map<String, dynamic>.from(raw as Map);
    return TapGameTapResult(
      score: (m['score'] as num).toInt(),
      staminaRemaining: (m['stamina'] as num).toInt(),
    );
  }

  @override
  Future<TapGameStaminaPurchaseResult> purchaseStamina({
    required String sessionId,
    required int tier,
  }) async {
    final raw = await _client.rpc<dynamic>(
      'tap_game_purchase_stamina',
      params: <String, dynamic>{
        'p_session_id': sessionId,
        'p_tier': tier,
      },
    );
    final m = Map<String, dynamic>.from(raw as Map);
    return TapGameStaminaPurchaseResult(
      stamina: (m['stamina'] as num).toInt(),
      added: (m['added'] as num).toInt(),
      spent: (m['spent'] as num).toInt(),
    );
  }

  @override
  Future<void> applyBoost(String sessionId) async {
    await _client.rpc<void>(
      'tap_game_apply_boost',
      params: <String, dynamic>{'p_session_id': sessionId},
    );
  }

  @override
  Future<int> applyJump(String sessionId) async {
    final v = await _client.rpc<int>(
      'tap_game_apply_jump',
      params: <String, dynamic>{'p_session_id': sessionId},
    );
    return v;
  }

  @override
  Future<void> applyShield(String sessionId) async {
    await _client.rpc<void>(
      'tap_game_apply_shield',
      params: <String, dynamic>{'p_session_id': sessionId},
    );
  }

  @override
  Future<void> finalizeSession(String sessionId) async {
    await _client.rpc<void>(
      'tap_game_finalize_session',
      params: <String, dynamic>{'p_session_id': sessionId},
    );
  }

  @override
  Future<int> claimMyReward(String sessionId) async {
    final v = await _client.rpc<int>(
      'tap_game_claim_my_reward',
      params: <String, dynamic>{'p_session_id': sessionId},
    );
    return v;
  }

  @override
  Future<List<TapGameLeaderboardEntry>> fetchLeaderboard(
    String sessionId, {
    int limit = 10,
  }) async {
    final rows = await _client
        .from(SupabaseConstants.tapGameScoresTable)
        .select('score, user_id, shield_ends_at, users(name, avatar)')
        .eq('session_id', sessionId)
        .order('score', ascending: false)
        .limit(limit);

    final list = rows as List<dynamic>;
    final now = DateTime.now();
    var rank = 0;
    return list.map((raw) {
      rank += 1;
      final e = Map<String, dynamic>.from(raw as Map);
      final uid = e['user_id'].toString();
      final users = e['users'];
      String name = 'Игрок';
      String? avatar;
      if (users is Map) {
        final u = Map<String, dynamic>.from(users);
        final n = u['name']?.toString().trim();
        if (n != null && n.isNotEmpty) name = n;
        final av = u['avatar']?.toString();
        avatar = (av != null && av.isNotEmpty) ? av : null;
      }
      DateTime? shieldEnd;
      final se = e['shield_ends_at'];
      if (se != null) {
        try {
          shieldEnd = DateTime.parse(se.toString());
        } catch (e) { debugPrint('$e'); }
      }
      final shieldActive =
          shieldEnd != null && shieldEnd.isAfter(now);
      final sc = (e['score'] as num?)?.toInt() ?? 0;
      return TapGameLeaderboardEntry(
        rank: rank,
        userId: uid,
        displayName: name,
        avatarUrl: avatar,
        score: sc,
        shieldActive: shieldActive,
      );
    }).toList(growable: false);
  }

  @override
  Future<int> spendQarmet({required int amount, required String reason}) async {
    final next = await _client.rpc<int>(
      'spend_qarmet',
      params: <String, dynamic>{
        'p_amount': amount,
        'p_reason': reason,
      },
    );
    return next;
  }

  @override
  Future<TapGameMyPlayState?> fetchMyPlayState({
    required String sessionId,
    required String userId,
  }) async {
    final row = await _client
        .from(SupabaseConstants.tapGameScoresTable)
        .select('score, stamina_remaining')
        .eq('session_id', sessionId)
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) return null;
    final m = Map<String, dynamic>.from(row as Map);
    return TapGameMyPlayState(
      score: (m['score'] as num?)?.toInt() ?? 0,
      staminaRemaining: (m['stamina_remaining'] as num?)?.toInt() ?? 0,
    );
  }
}
