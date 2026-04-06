import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/widgets/wow_entry_overlay.dart';
import '../../domain/entities/live_battle_lobby_player.dart';
import '../../domain/repositories/live_battle_repository.dart';

const _bg = Color(0xFF0A0A0F);
const _surface = Color(0xFF13131A);
const _purple = Color(0xFF7C3AED);
const _purpleLight = Color(0xFFAB6FFF);

class LiveBattleLobbyPage extends StatefulWidget {
  const LiveBattleLobbyPage({super.key});

  @override
  State<LiveBattleLobbyPage> createState() => _LiveBattleLobbyPageState();
}

class _LiveBattleLobbyPageState extends State<LiveBattleLobbyPage> {
  bool _loading = true;
  bool _onlineOnly = false;
  List<LiveBattleLobbyPlayer> _players = const [];
  final TextEditingController _searchController = TextEditingController();
  String _search = '';
  Timer? _searchDebounce;

  String? _challengingUserId;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadPlayers();
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      setState(() => _search = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPlayers() async {
    setState(() => _loading = true);
    try {
      final list = await context.read<LiveBattleRepository>().fetchLobbyPlayers();
      if (!mounted) return;
      setState(() {
        _players = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось загрузить игроков: $e')),
      );
    }
  }

  Future<void> _challenge(LiveBattleLobbyPlayer opponent) async {
    if (_challengingUserId != null) return;
    final meId = Supabase.instance.client.auth.currentUser?.id;
    if (meId == null) return;
    setState(() => _challengingUserId = opponent.id);
    try {
      final repo = context.read<LiveBattleRepository>();
      final battle = await repo.startBattle(meId, opponent.id);
      if (!mounted) return;
      context.push('/live-battle/${battle.id}');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось создать баттл: $e')),
      );
    } finally {
      if (mounted) setState(() => _challengingUserId = null);
    }
  }

  List<LiveBattleLobbyPlayer> get _filtered {
    return _players.where((u) {
      if (_onlineOnly && !u.isOnline) return false;
      if (_search.isEmpty) return true;
      final q = _search;
      return u.label.toLowerCase().contains(q);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final players = _filtered;
    final onlineCount = _players.where((u) => u.isOnline).length;
    final searchTheme = Theme.of(context).copyWith(
      brightness: Brightness.dark,
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: _purpleLight,
        selectionColor: Color(0x556366F1),
        selectionHandleColor: _purpleLight,
      ),
    );

    return WowEntryOverlay(
      type: WowEntryType.battle,
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).maybePop(),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'LIVE Battle',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          '$onlineCount онлайн сейчас',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => context.push('/live-battle-history'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [_purple, Color(0xFFEC4899)],
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.sports_kabaddi_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'BATTLE',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: _surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Theme(
                          data: searchTheme,
                          child: TextField(
                            controller: _searchController,
                            cursorColor: _purpleLight,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              filled: true,
                              fillColor: _surface,
                              hintText: 'Найти игрока...',
                              hintStyle: TextStyle(
                                color: Colors.white.withValues(alpha: 0.55),
                                fontSize: 14,
                              ),
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                color: Colors.white.withValues(alpha: 0.5),
                                size: 20,
                              ),
                              border: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 12,
                                horizontal: 4,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: () =>
                          setState(() => _onlineOnly = !_onlineOnly),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: _onlineOnly
                              ? _purple.withValues(alpha: 0.3)
                              : _surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _onlineOnly
                                ? _purpleLight.withValues(alpha: 0.5)
                                : Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _onlineOnly
                                    ? const Color(0xFF22C55E)
                                    : Colors.white.withValues(alpha: 0.3),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Online',
                              style: TextStyle(
                                color: _onlineOnly
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.5),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(color: _purpleLight),
                      )
                    : RefreshIndicator(
                        color: _purpleLight,
                        backgroundColor: _surface,
                        onRefresh: _loadPlayers,
                        child: players.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  SizedBox(
                                    height:
                                        MediaQuery.sizeOf(context).height * 0.25,
                                  ),
                                  Icon(
                                    Icons.person_search_rounded,
                                    size: 56,
                                    color: Colors.white.withValues(alpha: 0.2),
                                  ),
                                  const SizedBox(height: 12),
                                  Center(
                                    child: Text(
                                      _onlineOnly
                                          ? 'Нет игроков онлайн'
                                          : 'Игроки не найдены',
                                      style: TextStyle(
                                        color:
                                            Colors.white.withValues(alpha: 0.4),
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(
                                  parent: BouncingScrollPhysics(),
                                ),
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 24),
                                itemCount: players.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, i) {
                                  final p = players[i];
                                  final isChallenging =
                                      _challengingUserId == p.id;
                                  return _UserChallengeCard(
                                    player: p,
                                    isChallenging: isChallenging,
                                    isLocked: _challengingUserId != null &&
                                        !isChallenging,
                                    onChallenge: () => _challenge(p),
                                  );
                                },
                              ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserChallengeCard extends StatelessWidget {
  const _UserChallengeCard({
    required this.player,
    required this.isChallenging,
    required this.isLocked,
    required this.onChallenge,
  });

  final LiveBattleLobbyPlayer player;
  final bool isChallenging;
  final bool isLocked;
  final VoidCallback onChallenge;

  @override
  Widget build(BuildContext context) {
    final label = player.label;
    final avatar = player.avatarUrl ?? '';
    final raw = label.replaceFirst('@', '').trim();
    final initials = raw.isNotEmpty ? raw[0].toUpperCase() : '?';

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isChallenging
                ? _purpleLight.withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Row(
          children: [
            Stack(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _purple.withValues(alpha: 0.2),
                    image: avatar.isNotEmpty
                        ? DecorationImage(
                            image: NetworkImage(avatar),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: avatar.isEmpty
                      ? Center(
                          child: Text(
                            initials,
                            style: const TextStyle(
                              color: _purpleLight,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        )
                      : null,
                ),
                Positioned(
                  right: 1,
                  bottom: 1,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: player.isOnline
                          ? const Color(0xFF22C55E)
                          : Colors.white.withValues(alpha: 0.2),
                      border: Border.all(color: _surface, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: player.isOnline
                              ? const Color(0xFF22C55E)
                              : Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        player.isOnline ? 'Онлайн' : 'Не в сети',
                        style: TextStyle(
                          color: player.isOnline
                              ? const Color(0xFF22C55E)
                              : Colors.white.withValues(alpha: 0.35),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: isLocked || isChallenging ? null : onChallenge,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  gradient: isChallenging || isLocked
                      ? null
                      : const LinearGradient(
                          colors: [_purple, Color(0xFFEC4899)],
                        ),
                  color: isChallenging || isLocked
                      ? Colors.white.withValues(alpha: 0.07)
                      : null,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: isChallenging
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.sports_kabaddi_rounded,
                            color: isLocked
                                ? Colors.white.withValues(alpha: 0.25)
                                : Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Вызов',
                            style: TextStyle(
                              color: isLocked
                                  ? Colors.white.withValues(alpha: 0.25)
                                  : Colors.white,
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
    );
  }
}
