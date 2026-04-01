import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/repositories/live_battle_repository.dart';

class LiveBattleLobbyPage extends StatefulWidget {
  const LiveBattleLobbyPage({super.key});

  @override
  State<LiveBattleLobbyPage> createState() => _LiveBattleLobbyPageState();
}

class _LiveBattleLobbyPageState extends State<LiveBattleLobbyPage> {
  bool _loading = true;
  bool _creating = false;
  List<Map<String, dynamic>> _users = const [];
  final TextEditingController _searchController = TextEditingController();
  String _search = '';
  bool _onlineOnly = false;
  String? _hostA;
  String? _hostB;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _search = _searchController.text.trim().toLowerCase());
    });
    _loadUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    final client = Supabase.instance.client;
    try {
      final rows = await client
          .from('users')
          .select('id,username,email,updated_at')
          .order('created_at', ascending: false)
          .limit(100);
      final list = (rows as List<dynamic>).map((raw) {
        final row = Map<String, dynamic>.from(raw as Map);
        final id = (row['id'] ?? '').toString();
        final username = (row['username'] ?? '').toString();
        final email = (row['email'] ?? '').toString();
        final updatedAt =
            DateTime.tryParse((row['updated_at'] ?? '').toString())?.toUtc();
        final isOnline = updatedAt != null &&
            DateTime.now().toUtc().difference(updatedAt) <= const Duration(minutes: 5);
        return <String, dynamic>{
          'id': id,
          'username': username,
          'email': email,
          'label': username.isNotEmpty ? '@$username' : email,
          'is_online': isOnline,
        };
      }).where((e) => (e['id'] ?? '').isNotEmpty).toList(growable: false);
      if (!mounted) return;
      setState(() {
        _users = list;
        _hostA = list.isNotEmpty ? list.first['id'] : null;
        _hostB = list.length > 1 ? list[1]['id'] : null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _createBattle() async {
    if (_hostA == null || _hostB == null || _hostA == _hostB) return;
    setState(() => _creating = true);
    try {
      final repo = context.read<LiveBattleRepository>();
      final battle = await repo.startBattle(_hostA!, _hostB!);
      if (!mounted) return;
      context.push('/live-battle/${battle.id}');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Не удалось создать баттл: $e')));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  List<Map<String, dynamic>> get _filteredUsers {
    return _users.where((u) {
      if (_onlineOnly && u['is_online'] != true) return false;
      if (_search.isEmpty) return true;
      final username = (u['username'] ?? '').toString().toLowerCase();
      final email = (u['email'] ?? '').toString().toLowerCase();
      final label = (u['label'] ?? '').toString().toLowerCase();
      return username.contains(_search) ||
          email.contains(_search) ||
          label.contains(_search);
    }).toList(growable: false);
  }

  void _normalizeSelectedHosts() {
    final ids = _filteredUsers.map((e) => e['id'] as String).toSet();
    if (_hostA == null || !ids.contains(_hostA)) {
      _hostA = _filteredUsers.isNotEmpty ? _filteredUsers.first['id'] as String : null;
    }
    if (_hostB == null || !ids.contains(_hostB) || _hostB == _hostA) {
      final second = _filteredUsers
          .where((e) => (e['id'] as String) != _hostA)
          .toList(growable: false);
      _hostB = second.isNotEmpty ? second.first['id'] as String : null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    _normalizeSelectedHosts();
    final users = _filteredUsers;
    return Scaffold(
      appBar: AppBar(title: const Text('LIVE Battle Lobby')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Поиск по username/email',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Checkbox(
                  value: _onlineOnly,
                  onChanged: (v) => setState(() => _onlineOnly = v ?? false),
                ),
                const Expanded(
                  child: Text('Только online (по последней активности профиля)'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              key: ValueKey('hostA_${_hostA ?? 'none'}_${users.length}'),
              initialValue: _hostA,
              items: users
                  .map(
                    (u) => DropdownMenuItem<String>(
                      value: u['id'],
                      child: Text(u['label'] ?? ''),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (v) => setState(() => _hostA = v),
              decoration: const InputDecoration(
                labelText: 'Host A',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('hostB_${_hostB ?? 'none'}_${users.length}'),
              initialValue: _hostB,
              items: users
                  .map(
                    (u) => DropdownMenuItem<String>(
                      value: u['id'],
                      child: Text(u['label'] ?? ''),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (v) => setState(() => _hostB = v),
              decoration: const InputDecoration(
                labelText: 'Host B',
                border: OutlineInputBorder(),
              ),
            ),
            if (users.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Пользователи не найдены'),
              ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _creating ? null : _createBattle,
                icon: _creating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sports_kabaddi_rounded),
                label: const Text('Создать баттл'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
