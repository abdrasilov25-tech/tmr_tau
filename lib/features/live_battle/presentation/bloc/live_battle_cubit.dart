import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/gift.dart';
import '../../domain/entities/wallet.dart';
import '../../domain/repositories/live_battle_repository.dart';
import 'live_battle_state.dart';

class LiveBattleCubit extends Cubit<LiveBattleState> {
  LiveBattleCubit(this._repository) : super(const LiveBattleState());

  final LiveBattleRepository _repository;
  StreamSubscription? _battleSub;
  StreamSubscription? _topSub;
  Timer? _ticker;

  /// Дебаунс лайков отдельно по стороне (синяя / красная), как в TikTok.
  final Map<String, DateTime> _lastLikeAtByTarget = {};

  bool _finalizeOnceRequested = false;

  Future<void> init({required String battleId}) async {
    emit(state.copyWith(loading: true, error: null));
    _finalizeOnceRequested = false;
    _lastLikeAtByTarget.clear();
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) {
      emit(state.copyWith(loading: false, error: 'Пользователь не авторизован'));
      return;
    }
    try {
      final battle = await _repository.fetchBattle(battleId);
      if (battle == null) {
        emit(state.copyWith(loading: false, error: 'Баттл не найден'));
        return;
      }
      final results = await Future.wait<Object>([
        _repository.getWallet(currentUser.id),
        _repository.getGifts(),
      ]);
      final wallet = results[0] as Wallet;
      final gifts = results[1] as List<Gift>;
      final now = DateTime.now().toUtc();
      final remaining =
          battle.endTime.toUtc().difference(now).inSeconds;
      emit(
        state.copyWith(
          loading: false,
          battle: battle,
          gifts: gifts,
          wallet: wallet,
          remainingSeconds: remaining < 0 ? 0 : remaining,
        ),
      );

      _battleSub?.cancel();
      _battleSub = _repository.watchBattle(battleId).listen((b) {
        final t = DateTime.now().toUtc();
        final rem = b.endTime.toUtc().difference(t).inSeconds;
        emit(
          state.copyWith(
            loading: false,
            battle: b,
            remainingSeconds: rem < 0 ? 0 : rem,
          ),
        );
        if (!b.isActive) {
          _finalizeOnceRequested = true;
        }
      });
      _topSub?.cancel();
      _topSub = _repository.watchTopDonators(battleId).listen((top) {
        emit(state.copyWith(topDonators: top));
      });
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        final b = state.battle;
        if (b == null || isClosed) return;
        final rem =
            b.endTime.toUtc().difference(DateTime.now().toUtc()).inSeconds;
        emit(state.copyWith(remainingSeconds: rem < 0 ? 0 : rem));
        if (rem <= 0 && b.isActive && !_finalizeOnceRequested) {
          _finalizeOnceRequested = true;
          finalize();
        }
      });
    } catch (e) {
      emit(state.copyWith(loading: false, error: e.toString()));
    }
  }

  Future<void> sendLike({required String targetHost}) async {
    final battle = state.battle;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (battle == null || userId == null) return;

    final now = DateTime.now();
    final last = _lastLikeAtByTarget[targetHost];
    if (last != null && now.difference(last).inMilliseconds < 250) {
      return;
    }
    _lastLikeAtByTarget[targetHost] = now;
    try {
      await _repository.sendLike(
        battleId: battle.id,
        userId: userId,
        targetHost: targetHost,
      );
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
    }
  }

  Future<void> sendGift({required String giftId, required String targetHost}) async {
    final battle = state.battle;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (battle == null || userId == null) return;
    try {
      await _repository.sendGift(
        battleId: battle.id,
        giftId: giftId,
        senderId: userId,
        targetHost: targetHost,
      );
      final balance = await _repository.getBalance(userId);
      final currentWallet = state.wallet;
      emit(
        state.copyWith(
          wallet: currentWallet == null
              ? null
              : Wallet(userId: currentWallet.userId, balance: balance),
        ),
      );
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
    }
  }

  Future<void> finalize() async {
    final battle = state.battle;
    if (battle == null) return;
    try {
      await _repository.finishBattle(battle.id);
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
    }
  }

  @override
  Future<void> close() async {
    _ticker?.cancel();
    await _battleSub?.cancel();
    await _topSub?.cancel();
    return super.close();
  }
}
