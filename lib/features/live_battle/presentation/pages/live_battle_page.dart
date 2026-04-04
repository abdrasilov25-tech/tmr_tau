import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/agora_live_config.dart';
import '../../../live/presentation/live_battle_video_screen.dart';
import '../../domain/entities/live_battle.dart';
import '../../domain/entities/gift.dart';
import '../../domain/repositories/live_battle_repository.dart';
import '../bloc/live_battle_cubit.dart';
import '../bloc/live_battle_state.dart';

// ─────────────────────────────────────────────────────────────────
//  Entry point
// ─────────────────────────────────────────────────────────────────
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

// ─────────────────────────────────────────────────────────────────
//  Main view
// ─────────────────────────────────────────────────────────────────
class _BattleView extends StatefulWidget {
  const _BattleView();

  @override
  State<_BattleView> createState() => _BattleViewState();
}

class _BattleViewState extends State<_BattleView>
    with TickerProviderStateMixin {
  // Floating hearts for tap feedback
  final List<_HeartParticle> _heartsA = [];
  final List<_HeartParticle> _heartsB = [];

  // Gift panel visibility
  bool _showGifts = false;

  /// Сторона, которой уходит подарок (как в TikTok — выбор «команды»).
  bool _giftTargetIsA = true;

  void _spawnHeart(bool isA) {
    final rand = math.Random();
    final particle = _HeartParticle(
      id: rand.nextInt(999999),
      x: rand.nextDouble(),
      color: isA
          ? const Color(0xFF60A5FA)
          : const Color(0xFFF87171),
    );
    setState(() {
      if (isA) {
        _heartsA.add(particle);
      } else {
        _heartsB.add(particle);
      }
    });
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() {
        _heartsA.remove(particle);
        _heartsB.remove(particle);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: BlocConsumer<LiveBattleCubit, LiveBattleState>(
        listener: (context, state) {
          if (state.error != null && state.error!.isNotEmpty) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(state.error!)));
          }
        },
        builder: (context, state) {
          final battle = state.battle;

          if (state.loading || battle == null) {
            return const Scaffold(
              backgroundColor: Colors.black,
              body: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            );
          }

          final total = battle.scoreA + battle.scoreB;
          final ratioA = total == 0 ? 0.5 : battle.scoreA / total;
          final timer = _formatDuration(state.remainingSeconds);
          final isFinished = !battle.isActive || state.remainingSeconds <= 0;

          return Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              children: [
                // ── Split background ───────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF1E3A5F), Color(0xFF0A0A0F)],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topRight,
                            end: Alignment.bottomLeft,
                            colors: [Color(0xFF5F1E1E), Color(0xFF0A0A0F)],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                // ── Tap areas (full screen split) ──────────────
                if (!isFinished)
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            HapticFeedback.lightImpact();
                            setState(() => _giftTargetIsA = true);
                            _spawnHeart(true);
                            context
                                .read<LiveBattleCubit>()
                                .sendLike(targetHost: battle.hostA);
                          },
                          child: Container(color: Colors.transparent),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            HapticFeedback.lightImpact();
                            setState(() => _giftTargetIsA = false);
                            _spawnHeart(false);
                            context
                                .read<LiveBattleCubit>()
                                .sendLike(targetHost: battle.hostB);
                          },
                          child: Container(color: Colors.transparent),
                        ),
                      ),
                    ],
                  ),

                // ── Heart particles A ──────────────────────────
                for (final h in _heartsA)
                  Positioned(
                    left: MediaQuery.of(context).size.width * 0.25 * h.x +
                        MediaQuery.of(context).size.width * 0.02,
                    bottom: 200,
                    child: _FloatingHeart(
                      key: ValueKey(h.id),
                      color: h.color,
                    ),
                  ),

                // ── Heart particles B ──────────────────────────
                for (final h in _heartsB)
                  Positioned(
                    right: MediaQuery.of(context).size.width * 0.25 * h.x +
                        MediaQuery.of(context).size.width * 0.02,
                    bottom: 200,
                    child: _FloatingHeart(
                      key: ValueKey(h.id),
                      color: h.color,
                    ),
                  ),

                // ── Top HUD ────────────────────────────────────
                SafeArea(
                  child: Column(
                    children: [
                      _buildTopBar(context, battle, ratioA, timer, isFinished),
                      const Spacer(),
                      _buildHostScores(battle),
                      const SizedBox(height: 12),
                      if (!isFinished)
                        _buildTapHint()
                      else
                        _buildWinnerBanner(battle, state),
                      const SizedBox(height: 12),
                      _buildBottomPanel(context, state, battle, isFinished),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Top bar: back + VS label + timer + score bar ──────────────
  Widget _buildTopBar(
    BuildContext context,
    LiveBattle battle,
    double ratioA,
    String timer,
    bool isFinished,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              // Back
              GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
              const Spacer(),
              // LIVE badge + timer
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isFinished
                      ? Colors.grey.withValues(alpha: 0.3)
                      : Colors.red.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isFinished) ...[
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      isFinished ? 'ЗАВЕРШЁН' : timer,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  if (!AgoraLiveConfig.isConfigured) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Добавьте AGORA_APP_ID в .env для видео-режима баттла',
                        ),
                      ),
                    );
                    return;
                  }
                  final uid = Supabase.instance.client.auth.currentUser?.id;
                  if (uid == null) return;
                  final isParticipant =
                      uid == battle.hostA || uid == battle.hostB;
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => LiveBattleVideoScreen(
                        battleId: battle.id,
                        isHost: isParticipant,
                      ),
                    ),
                  );
                },
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.videocam_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Gifts toggle
              GestureDetector(
                onTap: () => setState(() => _showGifts = !_showGifts),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.card_giftcard_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Score ratio bar
          _ScoreRatioBar(ratioA: ratioA),
        ],
      ),
    );
  }

  // ── Host score cards ──────────────────────────────────────────
  Widget _buildHostScores(LiveBattle battle) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _HostScoreCard(
            label: 'HOST A',
            score: battle.scoreA,
            color: const Color(0xFF3B82F6),
            alignment: Alignment.centerLeft,
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15),
              ),
            ),
            child: const Text(
              'VS',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ),
          _HostScoreCard(
            label: 'HOST B',
            score: battle.scoreB,
            color: const Color(0xFFF43F5E),
            alignment: Alignment.centerRight,
          ),
        ],
      ),
    );
  }

  Widget _buildTapHint() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.touch_app_rounded,
          color: Colors.white.withValues(alpha: 0.4),
          size: 16,
        ),
        const SizedBox(width: 6),
        Text(
          'Тапай слева или справа чтобы поддержать',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildWinnerBanner(LiveBattle battle, LiveBattleState state) {
    final winnerLabel = battle.scoreA > battle.scoreB
        ? 'Host A победил!'
        : battle.scoreB > battle.scoreA
            ? 'Host B победил!'
            : 'Ничья!';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7C3AED), Color(0xFFEC4899)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Text(
            winnerLabel,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom panel: balance + gifts ─────────────────────────────
  Widget _buildBottomPanel(
    BuildContext context,
    LiveBattleState state,
    LiveBattle battle,
    bool isFinished,
  ) {
    return Column(
      children: [
        // Balance row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.monetization_on_rounded,
                      color: Color(0xFFF59E0B),
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${state.wallet?.balance ?? 0} Qarmet',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (!isFinished)
                GestureDetector(
                  onTap: () => setState(() => _showGifts = !_showGifts),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      gradient: _showGifts
                          ? const LinearGradient(
                              colors: [Color(0xFF7C3AED), Color(0xFFEC4899)],
                            )
                          : null,
                      color: _showGifts
                          ? null
                          : Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.card_giftcard_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Подарки',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),

        if (_showGifts && !isFinished && state.gifts.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                Text(
                  'Подарок для:',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment<bool>(
                        value: true,
                        label: Text('Синяя'),
                        icon: Icon(Icons.circle, size: 10, color: Color(0xFF60A5FA)),
                      ),
                      ButtonSegment<bool>(
                        value: false,
                        label: Text('Красная'),
                        icon: Icon(Icons.circle, size: 10, color: Color(0xFFF87171)),
                      ),
                    ],
                    selected: {_giftTargetIsA},
                    onSelectionChanged: (s) {
                      setState(() => _giftTargetIsA = s.first);
                    },
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: WidgetStateProperty.all(Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // Gift panel
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _showGifts && !isFinished && state.gifts.isNotEmpty
              ? _GiftPanel(
                  key: const ValueKey('gifts'),
                  gifts: state.gifts,
                  onGift: (giftId) {
                    context.read<LiveBattleCubit>().sendGift(
                          giftId: giftId,
                          targetHost:
                              _giftTargetIsA ? battle.hostA : battle.hostB,
                        );
                  },
                )
              : const SizedBox.shrink(key: ValueKey('no_gifts')),
        ),

        // Top donators
        if (state.topDonators.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _TopDonatorsRow(donators: state.topDonators),
          ),
      ],
    );
  }

  String _formatDuration(int secs) {
    final s = secs < 0 ? 0 : secs;
    final mm = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }
}

// ─────────────────────────────────────────────────────────────────
//  Sub-widgets
// ─────────────────────────────────────────────────────────────────

class _ScoreRatioBar extends StatelessWidget {
  const _ScoreRatioBar({required this.ratioA});
  final double ratioA;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 8,
        child: Row(
          children: [
            Flexible(
              flex: (ratioA * 100).round().clamp(1, 99),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.5, end: ratioA),
                duration: const Duration(milliseconds: 400),
                builder: (_, v, __) => Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF3B82F6), Color(0xFF60A5FA)],
                    ),
                  ),
                ),
              ),
            ),
            Flexible(
              flex: ((1 - ratioA) * 100).round().clamp(1, 99),
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFF87171), Color(0xFFF43F5E)],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HostScoreCard extends StatelessWidget {
  const _HostScoreCard({
    required this.label,
    required this.score,
    required this.color,
    required this.alignment,
  });

  final String label;
  final int score;
  final Color color;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: alignment == Alignment.centerLeft
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.end,
          children: [
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$score',
              style: TextStyle(
                color: color,
                fontSize: 36,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
            Text(
              'очков',
              style: TextStyle(
                color: color.withValues(alpha: 0.6),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GiftPanel extends StatelessWidget {
  const _GiftPanel({
    super.key,
    required this.gifts,
    required this.onGift,
  });

  final List<Gift> gifts;
  final void Function(String giftId) onGift;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: gifts.map<Widget>((gift) {
          return GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              onGift(gift.id);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.15),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.card_giftcard_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    gift.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${gift.price}',
                    style: const TextStyle(
                      color: Color(0xFFF59E0B),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _TopDonatorsRow extends StatelessWidget {
  const _TopDonatorsRow({required this.donators});
  final List donators;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 14),
        const SizedBox(width: 6),
        Text(
          'Топ по очкам баттла: ',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 12,
          ),
        ),
        Expanded(
          child: Text(
            donators
                .take(3)
                .map((d) {
                  final id = (d.userId as String);
                  final short = id.length >= 6 ? id.substring(0, 6) : id;
                  return '#$short (${d.amount})';
                })
                .join(' • '),
            style: const TextStyle(
              color: Color(0xFFF59E0B),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  Heart animation
// ─────────────────────────────────────────────────────────────────

class _HeartParticle {
  _HeartParticle({required this.id, required this.x, required this.color});
  final int id;
  final double x;
  final Color color;
}

class _FloatingHeart extends StatefulWidget {
  const _FloatingHeart({super.key, required this.color});
  final Color color;

  @override
  State<_FloatingHeart> createState() => _FloatingHeartState();
}

class _FloatingHeartState extends State<_FloatingHeart>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;
  late Animation<double> _translateY;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _opacity = Tween(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.5, 1.0)),
    );
    _translateY = Tween(begin: 0.0, end: -80.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _scale = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.3, end: 1.2), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 70),
    ]).animate(_ctrl);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Transform.translate(
        offset: Offset(0, _translateY.value),
        child: Opacity(
          opacity: _opacity.value,
          child: Transform.scale(
            scale: _scale.value,
            child: Icon(
              Icons.favorite_rounded,
              color: widget.color,
              size: 32,
            ),
          ),
        ),
      ),
    );
  }
}
