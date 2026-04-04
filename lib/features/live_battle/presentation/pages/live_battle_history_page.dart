import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/battle_history_entry.dart';
import '../../domain/repositories/live_battle_repository.dart';

// ─────────────────────────────────────────────────────────────────
//  Colors
// ─────────────────────────────────────────────────────────────────
const _bg = Color(0xFF0A0A0F);
const _surface = Color(0xFF13131A);
const _purple = Color(0xFF7C3AED);
const _purpleLight = Color(0xFFAB6FFF);
const _green = Color(0xFF22C55E);
const _red = Color(0xFFEF4444);
const _amber = Color(0xFFF59E0B);
const _textPrimary = Colors.white;
final _textSecondary = Colors.white.withValues(alpha: 0.5);

class LiveBattleHistoryPage extends StatefulWidget {
  const LiveBattleHistoryPage({super.key});

  @override
  State<LiveBattleHistoryPage> createState() => _LiveBattleHistoryPageState();
}

class _LiveBattleHistoryPageState extends State<LiveBattleHistoryPage>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  List<BattleHistoryEntry> _items = const [];
  String? _currentUserId;
  late AnimationController _fadeCtrl;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _load();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (_currentUserId == null) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }
    try {
      final repo = context.read<LiveBattleRepository>();
      final history = await repo.getBattleHistory(_currentUserId!);
      if (!mounted) return;
      setState(() {
        _items = history;
        _loading = false;
      });
      _fadeCtrl.forward();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // ── Stats ──────────────────────────────────────────────────────
  int get _wins =>
      _items.where((e) => e.winnerId == _currentUserId).length;
  int get _losses => _items
      .where((e) => e.winnerId != null && e.winnerId != _currentUserId)
      .length;
  int get _draws => _items.where((e) => e.winnerId == null).length;
  double get _winRate =>
      _items.isEmpty ? 0.0 : _wins / _items.length;

  // ── Top 5 battles by total score (for chart) ──────────────────
  List<BattleHistoryEntry> get _topByScore {
    final sorted = [..._items]
      ..sort(
        (a, b) => (b.scoreA + b.scoreB).compareTo(a.scoreA + a.scoreB),
      );
    return sorted.take(5).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: _purpleLight),
            )
          : FadeTransition(
              opacity: _fadeCtrl,
              child: CustomScrollView(
                slivers: [
                  _buildSliverAppBar(),
                  if (_items.isEmpty)
                    _buildEmptyState()
                  else ...[
                    SliverToBoxAdapter(child: _buildStatsRow()),
                    SliverToBoxAdapter(child: _buildWinRateBar()),
                    if (_topByScore.isNotEmpty)
                      SliverToBoxAdapter(child: _buildTopChart()),
                    SliverToBoxAdapter(child: _buildSectionHeader('История баттлов')),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => _BattleCard(
                          entry: _items[i],
                          currentUserId: _currentUserId,
                          index: i,
                        ),
                        childCount: _items.length,
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 40)),
                  ],
                ],
              ),
            ),
    );
  }

  // ── Sliver AppBar ─────────────────────────────────────────────
  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 160,
      pinned: true,
      backgroundColor: _bg,
      foregroundColor: _textPrimary,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        title: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_purple, Color(0xFFEC4899)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.sports_kabaddi_rounded,
                color: Colors.white,
                size: 16,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'История баттлов',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 17,
              ),
            ),
          ],
        ),
        background: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF2D1B69), _bg],
                ),
              ),
            ),
            Positioned(
              right: -30,
              top: -20,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _purple.withValues(alpha: 0.12),
                ),
              ),
            ),
            Positioned(
              left: -20,
              bottom: 0,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFEC4899).withValues(alpha: 0.08),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Empty state ───────────────────────────────────────────────
  Widget _buildEmptyState() {
    return SliverFillRemaining(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _purple.withValues(alpha: 0.12),
              ),
              child: const Icon(
                Icons.sports_kabaddi_rounded,
                size: 44,
                color: _purpleLight,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Ещё ни одного баттла',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Бросай вызов — первый бой ждёт!',
              style: TextStyle(color: _textSecondary, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  // ── Stats row ─────────────────────────────────────────────────
  Widget _buildStatsRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: _StatTile(
              label: 'Победы',
              value: '$_wins',
              color: _green,
              icon: Icons.emoji_events_rounded,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatTile(
              label: 'Поражения',
              value: '$_losses',
              color: _red,
              icon: Icons.close_rounded,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatTile(
              label: 'Ничьи',
              value: '$_draws',
              color: _amber,
              icon: Icons.handshake_rounded,
            ),
          ),
        ],
      ),
    );
  }

  // ── Win rate bar ──────────────────────────────────────────────
  Widget _buildWinRateBar() {
    final pct = (_winRate * 100).toStringAsFixed(0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Процент побед',
                  style: TextStyle(
                    color: _textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '$pct%',
                  style: const TextStyle(
                    color: _purpleLight,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: _winRate),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (_, value, __) => LinearProgressIndicator(
                  value: value,
                  minHeight: 10,
                  backgroundColor: Colors.white.withValues(alpha: 0.07),
                  valueColor: const AlwaysStoppedAnimation<Color>(_purpleLight),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$_wins из ${_items.length} баттлов',
                  style: TextStyle(color: _textSecondary, fontSize: 12),
                ),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: _green,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text('П', style: TextStyle(color: _textSecondary, fontSize: 11)),
                    const SizedBox(width: 8),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.07),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text('Пр', style: TextStyle(color: _textSecondary, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Top battles chart ─────────────────────────────────────────
  Widget _buildTopChart() {
    final top = _topByScore;
    final maxScore = top.fold<int>(
      1,
      (prev, e) => math.max(prev, e.scoreA + e.scoreB),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: _purple.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.bar_chart_rounded,
                    color: _purpleLight,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Топ по очкам',
                  style: TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                Text(
                  'Топ ${top.length}',
                  style: TextStyle(color: _textSecondary, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Bar chart
            SizedBox(
              height: 120,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: top.asMap().entries.map((entry) {
                  final i = entry.key;
                  final e = entry.value;
                  final total = e.scoreA + e.scoreB;
                  final heightRatio = total / maxScore;
                  final isWon = e.winnerId == _currentUserId;
                  final isDraw = e.winnerId == null;
                  final color = isWon
                      ? _green
                      : isDraw
                          ? _amber
                          : _red;
                  final medals = ['🥇', '🥈', '🥉', '4', '5'];
                  return _BarColumn(
                    heightRatio: heightRatio,
                    color: color,
                    label: medals[i],
                    value: total,
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _LegendDot(color: _green, label: 'Победа'),
                const SizedBox(width: 14),
                _LegendDot(color: _amber, label: 'Ничья'),
                const SizedBox(width: 14),
                _LegendDot(color: _red, label: 'Поражение'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 16,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [_purple, Color(0xFFEC4899)],
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: _textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          const Spacer(),
          Text(
            '${_items.length} баттлов',
            style: TextStyle(color: _textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  Battle card
// ─────────────────────────────────────────────────────────────────
class _BattleCard extends StatelessWidget {
  const _BattleCard({
    required this.entry,
    required this.currentUserId,
    required this.index,
  });

  final BattleHistoryEntry entry;
  final String? currentUserId;
  final int index;

  @override
  Widget build(BuildContext context) {
    final isWon = entry.winnerId == currentUserId;
    final isDraw = entry.winnerId == null;
    final outcomeColor = isWon ? _green : isDraw ? _amber : _red;
    final outcomeLabel = isWon ? 'ПОБЕДА' : isDraw ? 'НИЧЬЯ' : 'ПОРАЖЕНИЕ';
    final outcomeIcon = isWon
        ? Icons.emoji_events_rounded
        : isDraw
            ? Icons.handshake_rounded
            : Icons.close_rounded;

    final total = entry.scoreA + entry.scoreB;
    final ratioA = total == 0 ? 0.5 : entry.scoreA / total;

    final shortId = entry.battleId.length >= 8
        ? entry.battleId.substring(0, 8).toUpperCase()
        : entry.battleId.toUpperCase();

    final dateStr = _formatDate(entry.createdAt);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Container(
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: outcomeColor.withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: outcomeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(outcomeIcon, color: outcomeColor, size: 13),
                        const SizedBox(width: 4),
                        Text(
                          outcomeLabel,
                          style: TextStyle(
                            color: outcomeColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '#$shortId',
                    style: TextStyle(
                      color: _textSecondary,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    dateStr,
                    style: TextStyle(color: _textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),

            // ── Score row ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${entry.scoreA}',
                    style: const TextStyle(
                      color: _textPrimary,
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'VS',
                      style: TextStyle(
                        color: _textSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  Text(
                    '${entry.scoreB}',
                    style: const TextStyle(
                      color: _textPrimary,
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),

            // ── Score bar ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  height: 5,
                  child: Row(
                    children: [
                      Flexible(
                        flex: (ratioA * 100).round().clamp(1, 99),
                        child: Container(
                          color: const Color(0xFF3B82F6),
                        ),
                      ),
                      Flexible(
                        flex: ((1 - ratioA) * 100).round().clamp(1, 99),
                        child: Container(
                          color: const Color(0xFFF43F5E),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Footer ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              child: Row(
                children: [
                  Icon(Icons.star_rounded, color: _amber, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    'MVP: ${entry.maybeMvpSenderId != null ? '#${entry.maybeMvpSenderId!.substring(0, math.min(6, entry.maybeMvpSenderId!.length))}' : '—'}',
                    style: TextStyle(color: _textSecondary, fontSize: 12),
                  ),
                  const Spacer(),
                  Text(
                    'Сумма: $total очков',
                    style: TextStyle(
                      color: _textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final mo = local.month.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final mi = local.minute.toString().padLeft(2, '0');
    return '$d.$mo  $h:$mi';
  }
}

// ─────────────────────────────────────────────────────────────────
//  Sub-widgets
// ─────────────────────────────────────────────────────────────────

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _BarColumn extends StatelessWidget {
  const _BarColumn({
    required this.heightRatio,
    required this.color,
    required this.label,
    required this.value,
  });

  final double heightRatio;
  final Color color;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          '$value',
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: heightRatio),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (_, v, __) => ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            child: Container(
              width: 36,
              height: 80 * v + 4,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [color, color.withValues(alpha: 0.6)],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
