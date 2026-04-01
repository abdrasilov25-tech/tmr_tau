import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/battle_history_entry.dart';
import '../../domain/repositories/live_battle_repository.dart';

class LiveBattleHistoryPage extends StatefulWidget {
  const LiveBattleHistoryPage({super.key});

  @override
  State<LiveBattleHistoryPage> createState() => _LiveBattleHistoryPageState();
}

class _LiveBattleHistoryPageState extends State<LiveBattleHistoryPage> {
  bool _loading = true;
  List<BattleHistoryEntry> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }
    try {
      final repo = context.read<LiveBattleRepository>();
      final history = await repo.getBattleHistory(userId);
      if (!mounted) return;
      setState(() {
        _items = history;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('История баттлов')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? const Center(child: Text('История пока пустая'))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _items.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = _items[index];
                final winner = item.winnerId == null ? 'Ничья' : item.winnerId!;
                return Card(
                  child: ListTile(
                    title: Text('Баттл ${item.battleId.substring(0, 8)}'),
                    subtitle: Text(
                      'Счёт: ${item.scoreA} : ${item.scoreB}\nПобедитель: $winner\nMVP: ${item.maybeMvpSenderId ?? '-'}',
                    ),
                    isThreeLine: true,
                  ),
                );
              },
            ),
    );
  }
}
