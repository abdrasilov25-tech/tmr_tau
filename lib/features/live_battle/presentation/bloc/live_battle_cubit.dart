import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/wallet.dart';
import '../../domain/repositories/live_battle_repository.dart';
import 'live_battle_state.dart';

class LiveBattleCubit extends Cubit<LiveBattleState> {
  LiveBattleCubit(this._repository) : super(const LiveBattleState());

  final LiveBattleRepository _repository;
  StreamSubscription? _battleSub;
  StreamSubscription? _topSub;
  Timer? _ticker;

  Future<void> init({required String battleId}) async {
    emit(state.copyWith(loading: true, error: null));
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) {
      emit(state.copyWith(loading: false, error: 'Пользователь не авторизован'));
      return;
    }
    try {
      final wallet = await _repository.getWallet(currentUser.id);
      final gifts = await _repository.getGifts();
      _battleSub?.cancel();
      _battleSub = _repository.watchBattle(battleId).listen((battle) {
        final now = DateTime.now().toUtc();
        final remaining = battle.endTime.toUtc().difference(now).inSeconds;
        emit(
          state.copyWith(
            loading: false,
            battle: battle,
            gifts: gifts,
            wallet: wallet,
            remainingSeconds: remaining < 0 ? 0 : remaining,
          ),
        );
      });
      _topSub?.cancel();
      _topSub = _repository.watchTopDonators(battleId).listen((top) {
        emit(state.copyWith(topDonators: top));
      });
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        final battle = state.battle;
        if (battle == null || isClosed) return;
        final remaining = battle.endTime.toUtc().difference(DateTime.now().toUtc()).inSeconds;
        emit(state.copyWith(remainingSeconds: remaining < 0 ? 0 : remaining));
        if (remaining <= 0 && battle.isActive) {
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

    // Client-side debounce + backend rate limit.
    final now = DateTime.now();
    final lastLikeAt = state.lastLikeAt;
    if (lastLikeAt != null && now.difference(lastLikeAt).inMilliseconds < 250) {
      return;
    }
    emit(state.copyWith(lastLikeAt: now));
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
