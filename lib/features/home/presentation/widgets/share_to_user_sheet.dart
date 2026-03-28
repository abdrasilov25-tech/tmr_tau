import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import '../../../../core/widgets/cached_avatar.dart';

/// Данные строки пользователя в списке «Поделиться».
class ShareUserRow {
  const ShareUserRow({
    required this.userId,
    required this.name,
    this.avatarUrl,
  });

  final String userId;
  final String name;
  final String? avatarUrl;
}

/// Bottom-sheet для выбора пользователя, которому отправить шаринг.
/// Возвращает [ShareUserRow] или `null`, если пользователь закрыл лист.
class ShareToUserSheet extends StatefulWidget {
  const ShareToUserSheet({super.key, required this.currentUserId});

  final String currentUserId;

  @override
  State<ShareToUserSheet> createState() => _ShareToUserSheetState();
}

class _ShareToUserSheetState extends State<ShareToUserSheet> {
  final _searchController = TextEditingController();
  bool _loading = false;
  String? _error;

  List<ShareUserRow> _users = [];

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load(String q) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = supa.Supabase.instance.client;
      final trimmed = q.trim();
      final res = trimmed.isNotEmpty
          ? await client
              .from('users')
              .select('id,name,avatar')
              .neq('id', widget.currentUserId)
              .ilike('name', '%$trimmed%')
              .limit(20)
          : await client
              .from('users')
              .select('id,name,avatar')
              .neq('id', widget.currentUserId)
              .limit(20);

      final list = res as List<dynamic>;
      final mapped = list.map((e) {
        final m = e as Map<String, dynamic>;
        return ShareUserRow(
          userId: m['id'] as String,
          name: (m['name'] as String?) ?? 'Пользователь',
          avatarUrl: m['avatar'] as String?,
        );
      }).toList(growable: false);

      if (!mounted) return;
      setState(() {
        _users = mapped;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Поделиться с другом',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              )
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(
                  const Duration(milliseconds: 350), () => _load(v));
            },
            decoration: const InputDecoration(
              hintText: 'Поиск по имени...',
              hintStyle: TextStyle(color: Colors.white54),
              filled: true,
              fillColor: Color(0xFF111827),
              border: OutlineInputBorder(),
              prefixIcon:
                  Icon(Icons.search_rounded, color: Colors.white70),
            ),
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Ошибка: $_error',
                style: const TextStyle(color: Colors.redAccent),
              ),
            )
          else if (_users.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Никто не найден',
                style: TextStyle(color: Colors.white70),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: _users.length,
                separatorBuilder: (_, _) =>
                    const Divider(color: Colors.white12, height: 1),
                itemBuilder: (context, index) {
                  final u = _users[index];
                  return ListTile(
                    leading: CachedAvatar(
                      imageUrl: u.avatarUrl?.isNotEmpty == true
                          ? u.avatarUrl
                          : null,
                      radius: 20,
                      fallbackText: u.name,
                    ),
                    title: Text(
                      u.name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded,
                        color: Colors.white60),
                    onTap: () => Navigator.of(context).pop(u),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
