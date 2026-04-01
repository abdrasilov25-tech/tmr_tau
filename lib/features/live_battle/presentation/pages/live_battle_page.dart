import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/repositories/live_battle_repository.dart';
import '../bloc/live_battle_cubit.dart';
import '../bloc/live_battle_state.dart';

class LiveBattlePage extends StatelessWidget {
  const LiveBattlePage({super.key, required this.battleId});

  final String battleId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          LiveBattleCubit(context.read<LiveBattleRepository>())
            ..init(battleId: battleId),
      child: const _BattleView(),
    );
  }
}

class _BattleView extends StatelessWidget {
  const _BattleView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<LiveBattleCubit, LiveBattleState>(
      listener: (context, state) {
        final error = state.error;
        if (error == null || error.isEmpty) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      },
      builder: (context, state) {
        final battle = state.battle;
        if (state.loading || battle == null) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final timer = _formatDuration(state.remainingSeconds);
        return Scaffold(
          appBar: AppBar(title: const Text('LIVE Баттл')),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: _HostCard(
                        title: 'Host A',
                        hostId: battle.hostA,
                        score: battle.scoreA,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Column(
                        children: [
                          const Text('VS', style: TextStyle(fontWeight: FontWeight.w900)),
                          Text(timer),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _HostCard(
                        title: 'Host B',
                        hostId: battle.hostB,
                        score: battle.scoreB,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Баланс: ${state.wallet?.balance ?? 0} Qarmet',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () => context.read<LiveBattleCubit>().sendLike(
                    targetHost: battle.hostA,
                  ),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.shade50,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Center(
                      child: Text('Тапай для лайка (+1, в последние 30с x2)'),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 58,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  scrollDirection: Axis.horizontal,
                  itemCount: state.gifts.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final gift = state.gifts[i];
                    return ActionChip(
                      label: Text('${gift.name} • ${gift.price}'),
                      onPressed: () => context.read<LiveBattleCubit>().sendGift(
                        giftId: gift.id,
                        targetHost: battle.hostA,
                      ),
                    );
                  },
                ),
              ),
              Container(
                margin: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Top-3 донатеров', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    ...state.topDonators.map(
                      (d) => Text('${d.userId.substring(0, 6)}…  ${d.amount} Qarmet'),
                    ),
                    const SizedBox(height: 6),
                    Text('MVP: ${state.mvpUserId?.substring(0, 6) ?? '-'}'),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDuration(int secs) {
    final s = secs < 0 ? 0 : secs;
    final mm = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }
}

class _HostCard extends StatelessWidget {
  const _HostCard({
    required this.title,
    required this.hostId,
    required this.score,
  });

  final String title;
  final String hostId;
  final int score;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          Text('@${hostId.substring(0, 6)}…'),
          const SizedBox(height: 8),
          Text('$score', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}
