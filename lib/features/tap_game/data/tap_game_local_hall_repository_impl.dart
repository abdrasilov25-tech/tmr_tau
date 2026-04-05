import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/entities/tap_game_leaderboard_entry.dart';
import '../domain/entities/tap_game_local_hall_entry.dart';
import '../domain/repositories/tap_game_local_hall_repository.dart';

class TapGameLocalHallRepositoryImpl implements TapGameLocalHallRepository {
  static const _prefsKey = 'tap_game_local_hall_v1';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  @override
  Future<List<TapGameLocalHallEntry>> getTop50() async {
    final raw = (await _prefs).getString(_prefsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final out = <TapGameLocalHallEntry>[];
      for (final e in list) {
        if (e is Map) {
          final ent = TapGameLocalHallEntry.fromJson(
            Map<String, dynamic>.from(e),
          );
          if (ent != null) out.add(ent);
        }
      }
      out.sort((a, b) => b.bestScore.compareTo(a.bestScore));
      return out.take(TapGameLocalHallRepository.maxEntries).toList(
            growable: false,
          );
    } catch (_) {
      return const [];
    }
  }

  Future<void> _save(List<TapGameLocalHallEntry> entries) async {
    final sorted = [...entries]
      ..sort((a, b) => b.bestScore.compareTo(a.bestScore));
    final top = sorted.take(TapGameLocalHallRepository.maxEntries).toList();
    final jsonStr = jsonEncode(top.map((e) => e.toJson()).toList());
    await (await _prefs).setString(_prefsKey, jsonStr);
  }

  @override
  Future<void> mergeFromLeaderboard(
    List<TapGameLeaderboardEntry> entries,
  ) async {
    if (entries.isEmpty) return;
    final current = await getTop50();
    final byId = <String, TapGameLocalHallEntry>{
      for (final e in current) e.userId: e,
    };
    final now = DateTime.now();
    for (final row in entries) {
      final prev = byId[row.userId];
      final nextScore = math.max(prev?.bestScore ?? 0, row.score);
      byId[row.userId] = TapGameLocalHallEntry(
        userId: row.userId,
        displayName: row.displayName,
        avatarUrl: row.avatarUrl ?? prev?.avatarUrl,
        bestScore: nextScore,
        updatedAt: now,
      );
    }
    await _save(byId.values.toList());
  }

  @override
  Future<void> recordMyBestScore({
    required String userId,
    required String displayName,
    String? avatarUrl,
    required int score,
  }) async {
    if (score <= 0) return;
    final current = await getTop50();
    final byId = <String, TapGameLocalHallEntry>{
      for (final e in current) e.userId: e,
    };
    final prev = byId[userId];
    final nextScore = math.max(prev?.bestScore ?? 0, score);
    byId[userId] = TapGameLocalHallEntry(
      userId: userId,
      displayName: displayName,
      avatarUrl: avatarUrl ?? prev?.avatarUrl,
      bestScore: nextScore,
      updatedAt: DateTime.now(),
    );
    await _save(byId.values.toList());
  }
}
