import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/datasources/map_remote_datasource.dart';
import '../../domain/entities/map_leaderboard_entry.dart';

class MapLeaderboardSheet extends StatefulWidget {
  const MapLeaderboardSheet({super.key, required this.dataSource});

  final MapRemoteDataSource dataSource;

  @override
  State<MapLeaderboardSheet> createState() => _MapLeaderboardSheetState();
}

class _MapLeaderboardSheetState extends State<MapLeaderboardSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  List<MapLeaderboardEntry>? _global;
  List<MapLeaderboardEntry>? _friends;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final global = await widget.dataSource.getMapLeaderboard();
      final friends = await widget.dataSource.getFriendLeaderboard();
      if (!mounted) return;
      setState(() {
        _global = global;
        _friends = friends;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text('🏅', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Рейтинг на карте',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('За текущий месяц',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                  ],
                ),
                const Spacer(),
                // Score legend
                GestureDetector(
                  onTap: _showLegend,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(children: [
                      Icon(Icons.info_outline_rounded, size: 14, color: Colors.grey),
                      SizedBox(width: 4),
                      Text('Как считается?',
                          style: TextStyle(fontSize: 11, color: Colors.grey)),
                    ]),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(4),
              child: TabBar(
                controller: _tabs,
                indicator: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 4,
                    ),
                  ],
                ),
                labelColor: Colors.black87,
                unselectedLabelColor: Colors.grey,
                labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                tabs: const [
                  Tab(text: '🌍 Глобальный'),
                  Tab(text: '👥 Друзья'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabs,
                    children: [
                      _LeaderboardList(
                        entries: _global ?? [],
                        onProfileTap: (uid) {
                          Navigator.of(context).pop();
                          context.push('/profile/$uid');
                        },
                      ),
                      _LeaderboardList(
                        entries: _friends ?? [],
                        onProfileTap: (uid) {
                          Navigator.of(context).pop();
                          context.push('/profile/$uid');
                        },
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  void _showLegend() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Как считается рейтинг?'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LegendRow(icon: '⚡', text: 'Квест выполнен = +1 очко'),
            _LegendRow(icon: '🏆', text: 'Ставка в аукционе = +5 очков'),
            _LegendRow(icon: '📍', text: 'Буст на карте = +3 очка'),
            _LegendRow(icon: '🌐', text: 'Zone Takeover = +20 очков'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
  }
}

class _LeaderboardList extends StatelessWidget {
  const _LeaderboardList({required this.entries, required this.onProfileTap});

  final List<MapLeaderboardEntry> entries;
  final void Function(String uid) onProfileTap;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🌱', style: TextStyle(fontSize: 48)),
            SizedBox(height: 12),
            Text('Пока никого нет.\nБудьте первым!',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: entries.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _LeaderboardTile(
        entry: entries[i],
        rank: i + 1,
        onTap: () => onProfileTap(entries[i].userId),
      ),
    );
  }
}

class _LeaderboardTile extends StatelessWidget {
  const _LeaderboardTile({
    required this.entry,
    required this.rank,
    required this.onTap,
  });

  final MapLeaderboardEntry entry;
  final int rank;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final medal = switch (rank) {
      1 => '🥇',
      2 => '🥈',
      3 => '🥉',
      _ => null,
    };

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: entry.isMe
              ? const Color(0xFF2563EB).withValues(alpha: 0.06)
              : rank <= 3
                  ? const Color(0xFFFEF9C3).withValues(alpha: 0.5)
                  : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: entry.isMe
                ? const Color(0xFF93C5FD)
                : rank <= 3
                    ? const Color(0xFFFDE68A)
                    : Colors.grey.shade200,
          ),
        ),
        child: Row(
          children: [
            // Rank
            SizedBox(
              width: 36,
              child: medal != null
                  ? Text(medal, style: const TextStyle(fontSize: 22),
                      textAlign: TextAlign.center)
                  : Text('#$rank',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.grey.shade500),
                      textAlign: TextAlign.center),
            ),
            const SizedBox(width: 10),
            // Avatar
            CircleAvatar(
              radius: 20,
              backgroundColor: Colors.grey.shade200,
              backgroundImage: entry.userAvatarUrl != null
                  ? CachedNetworkImageProvider(entry.userAvatarUrl!)
                  : null,
              child: entry.userAvatarUrl == null
                  ? const Icon(Icons.person, size: 18, color: Colors.grey)
                  : null,
            ),
            const SizedBox(width: 12),
            // Name
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      entry.userName,
                      style: TextStyle(
                        fontWeight: entry.isMe ? FontWeight.bold : FontWeight.w600,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (entry.isMe) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2563EB),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('Вы',
                          style: TextStyle(fontSize: 9, color: Colors.white,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ],
              ),
            ),
            // Score
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${entry.score}',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: rank == 1
                            ? const Color(0xFFF59E0B)
                            : const Color(0xFF1A1A1A))),
                const Text('очков',
                    style: TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.icon, required this.text}); // ignore: unused_element
  final String icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Text(icon, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 10),
        Text(text, style: const TextStyle(fontSize: 13)),
      ]),
    );
  }
}
