import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/supabase_constants.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../domain/entities/post_entity.dart';

class PostShareSheet extends StatefulWidget {
  const PostShareSheet({
    super.key,
    required this.currentUserId,
    required this.post,
    required this.onAddToStory,
  });

  final String currentUserId;
  final PostEntity post;
  final Future<void> Function() onAddToStory;

  @override
  State<PostShareSheet> createState() => _PostShareSheetState();
}

class _PostShareSheetState extends State<PostShareSheet> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _sentToUserIds = <String>{};

  bool _loading = true;
  String? _error;
  List<_ShareUser> _allFriends = const <_ShareUser>[];
  List<_ShareUser> _filteredFriends = const <_ShareUser>[];

  @override
  void initState() {
    super.initState();
    _loadFriends();
    _searchController.addListener(_applySearch);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_applySearch)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      final followingRows = await client
          .from(SupabaseConstants.followersTable)
          .select('following_id')
          .eq('follower_id', widget.currentUserId)
          .limit(300);

      final followingIds = (followingRows as List<dynamic>)
          .map((e) => (e as Map<String, dynamic>)['following_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList(growable: false);

      if (followingIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          _allFriends = const <_ShareUser>[];
          _filteredFriends = const <_ShareUser>[];
          _loading = false;
        });
        return;
      }

      final usersRows = await client
          .from(SupabaseConstants.usersTable)
          .select('id,name,avatar')
          .inFilter('id', followingIds);

      final users = (usersRows as List<dynamic>)
          .map((e) => e as Map<String, dynamic>)
          .map(
            (row) => _ShareUser(
              id: (row['id'] ?? '').toString(),
              name: ((row['name'] ?? '').toString()).trim().isEmpty
                  ? 'Пользователь'
                  : (row['name'] as String),
              avatarUrl: (row['avatar'] as String?)?.trim().isEmpty == true
                  ? null
                  : row['avatar'] as String?,
            ),
          )
          .where((u) => u.id.isNotEmpty && u.id != widget.currentUserId)
          .toList(growable: false)
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      if (!mounted) return;
      setState(() {
        _allFriends = users;
        _filteredFriends = users;
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

  void _applySearch() {
    final q = _searchController.text.trim().toLowerCase();
    if (!mounted) return;
    setState(() {
      if (q.isEmpty) {
        _filteredFriends = _allFriends;
      } else {
        _filteredFriends = _allFriends
            .where((u) => u.name.toLowerCase().contains(q))
            .toList(growable: false);
      }
    });
  }

  String _buildStructuredPostMessage() {
    String enc(String value) => Uri.encodeComponent(value);
    final primaryImage = widget.post.displayImageUrls.isNotEmpty
        ? widget.post.displayImageUrls.first
        : '';
    return '__post__|${enc(widget.post.id)}|${enc(primaryImage)}|'
        '${enc(widget.post.caption.trim())}|'
        '${enc(widget.post.userName ?? 'Пользователь')}|'
        '${enc(widget.post.videoUrl ?? '')}|'
        '${widget.post.likesCount}|${widget.post.commentsCount}|${widget.post.repostsCount}';
  }

  Future<void> _sendToFriend(_ShareUser friend) async {
    try {
      await Supabase.instance.client.from(SupabaseConstants.messagesTable).insert(
        {
          'sender_id': widget.currentUserId,
          'receiver_id': friend.id,
          'text': _buildStructuredPostMessage(),
        },
      );
      if (!mounted) return;
      setState(() => _sentToUserIds.add(friend.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Отправлено: ${friend.name}')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось отправить')),
      );
    }
  }

  Future<void> _shareWhatsApp() async {
    final link = 'https://tmr-tau.app/post/${widget.post.id}';
    final text = widget.post.caption.trim().isEmpty
        ? 'Смотри публикацию: $link'
        : '${widget.post.caption.trim()}\n$link';
    final uri = Uri.parse('whatsapp://send?text=${Uri.encodeComponent(text)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      return;
    }
    await SharePlus.instance.share(ShareParams(text: text));
  }

  @override
  Widget build(BuildContext context) {
    final horizontalUsers = _filteredFriends.take(12).toList(growable: false);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.78,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Поделиться',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Поиск кому отправить',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Expanded(
                child: Center(
                  child: Text(
                    'Ошибка загрузки друзей',
                    style: TextStyle(color: Colors.red.shade400),
                  ),
                ),
              )
            else ...[
              SizedBox(
                height: 92,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  scrollDirection: Axis.horizontal,
                  itemCount: horizontalUsers.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final u = horizontalUsers[index];
                    return InkWell(
                      onTap: () => _sendToFriend(u),
                      borderRadius: BorderRadius.circular(40),
                      child: SizedBox(
                        width: 72,
                        child: Column(
                          children: [
                            Stack(
                              children: [
                                CachedAvatar(
                                  imageUrl: u.avatarUrl,
                                  radius: 24,
                                  fallbackText: u.name,
                                ),
                                if (_sentToUserIds.contains(u.id))
                                  const Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: Icon(
                                      Icons.check_circle_rounded,
                                      size: 18,
                                      color: Colors.green,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              u.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _filteredFriends.isEmpty
                    ? const Center(child: Text('Друзья не найдены'))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                        itemCount: _filteredFriends.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final u = _filteredFriends[index];
                          final sent = _sentToUserIds.contains(u.id);
                          return ListTile(
                            leading: CachedAvatar(
                              imageUrl: u.avatarUrl,
                              radius: 22,
                              fallbackText: u.name,
                            ),
                            title: Text(u.name),
                            trailing: FilledButton(
                              onPressed: sent ? null : () => _sendToFriend(u),
                              child: Text(sent ? 'Отправлено' : 'Отправить'),
                            ),
                          );
                        },
                      ),
              ),
            ],
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey.shade300)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await widget.onAddToStory();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Открыт экран добавления в историю')),
                        );
                      },
                      icon: const Icon(Icons.history_rounded),
                      label: const Text('Добавить в историю'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _shareWhatsApp,
                      icon: const Icon(Icons.chat_bubble_rounded),
                      label: const Text('WhatsApp'),
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
}

class _ShareUser {
  const _ShareUser({
    required this.id,
    required this.name,
    required this.avatarUrl,
  });

  final String id;
  final String name;
  final String? avatarUrl;
}
