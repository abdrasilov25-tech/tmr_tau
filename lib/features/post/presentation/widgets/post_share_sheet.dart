import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/supabase_constants.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../stories/domain/repositories/stories_repository.dart';
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
          .select('id,name,avatar,updated_at')
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
              lastActiveAt: DateTime.tryParse((row['updated_at'] ?? '').toString()),
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
    } catch (e) {
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

  Future<void> _shareInstagram() async {
    final link = 'https://tmr-tau.app/post/${widget.post.id}';
    final appUri = Uri.parse('instagram://app');
    if (await canLaunchUrl(appUri)) {
      await launchUrl(appUri, mode: LaunchMode.externalApplication);
      return;
    }
    await launchUrl(
      Uri.parse(link),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _shareThreads() async {
    final link = 'https://tmr-tau.app/post/${widget.post.id}';
    final text = widget.post.caption.trim().isEmpty
        ? 'Смотри публикацию: $link'
        : '${widget.post.caption.trim()}\n$link';
    final threadsWebIntent = Uri.parse(
      'https://www.threads.net/intent/post?text=${Uri.encodeComponent(text)}',
    );
    if (await canLaunchUrl(threadsWebIntent)) {
      await launchUrl(threadsWebIntent, mode: LaunchMode.externalApplication);
      return;
    }
    await SharePlus.instance.share(ShareParams(text: text));
  }

  Future<void> _addPostToStory() async {
    final imageUrl = widget.post.displayImageUrls.isNotEmpty
        ? widget.post.displayImageUrls.first
        : '';
    final videoUrl = widget.post.videoUrl;
    if (imageUrl.isEmpty && (videoUrl == null || videoUrl.trim().isEmpty)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('У публикации нет медиа для истории')),
      );
      return;
    }
    try {
      final storiesRepository = context.read<StoriesRepository>();
      final isForeignPost = widget.post.userId != widget.currentUserId;
      await storiesRepository.addStory(
        userId: widget.currentUserId,
        imageUrl: imageUrl,
        videoUrl: videoUrl,
        caption: widget.post.caption.trim().isEmpty ? null : widget.post.caption.trim(),
        originalPostId: isForeignPost ? widget.post.id : null,
        originalPostAuthorId: isForeignPost ? widget.post.userId : null,
        originalPostAuthorName: isForeignPost ? widget.post.userName : null,
        originalPostPreviewUrl: isForeignPost
            ? (imageUrl.isNotEmpty ? imageUrl : (videoUrl ?? ''))
            : null,
      );
      if (isForeignPost) {
        try {
          await Supabase.instance.client
              .from(SupabaseConstants.notificationsTable)
              .insert({
            'user_id': widget.post.userId,
            'actor_id': widget.currentUserId,
            'type': 'post_mention_story',
            'title': 'Вас упомянули в истории',
            'body': 'Вашу публикацию добавили в историю [post:${widget.post.id}]',
            'post_id': widget.post.id,
          });
        } catch (e) {
          // Mention-notification failure should not break sharing flow.
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Публикация добавлена в историю')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось добавить в историю')),
      );
    }
  }

  bool _isOnline(_ShareUser user) {
    final lastActiveAt = user.lastActiveAt;
    if (lastActiveAt == null) return false;
    return DateTime.now().difference(lastActiveAt).inMinutes <= 5;
  }

  String _statusText(_ShareUser user) {
    if (_isOnline(user)) return 'В сети';
    final lastActiveAt = user.lastActiveAt;
    if (lastActiveAt == null) return 'Был(а) недавно';
    final diff = DateTime.now().difference(lastActiveAt);
    if (diff.inMinutes < 60) return 'Был(а) ${diff.inMinutes}м назад';
    if (diff.inHours < 24) return 'Был(а) ${diff.inHours}ч назад';
    return 'Был(а) ${diff.inDays}д назад';
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade400,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Поиск',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: const Color(0xFFF3F5F7),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
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
                height: 104,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  scrollDirection: Axis.horizontal,
                  itemCount: horizontalUsers.length,
                  separatorBuilder: (_, index) => const SizedBox(width: 10),
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
                                  radius: 27,
                                  fallbackText: u.name,
                                ),
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: _isOnline(u)
                                          ? const Color(0xFF30D158)
                                          : Colors.grey.shade300,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                                if (_sentToUserIds.contains(u.id))
                                  const Positioned(
                                    left: 36,
                                    top: 36,
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
                        separatorBuilder: (_, index) => const Divider(height: 1),
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
                            subtitle: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: _isOnline(u)
                                        ? const Color(0xFF30D158)
                                        : Colors.grey.shade400,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _statusText(u),
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: _isOnline(u)
                                        ? const Color(0xFF23B14D)
                                        : Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
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
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey.shade300)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _ShareActionIcon(
                    icon: Icons.add_circle_outline_rounded,
                    label: 'В историю',
                    backgroundColor: const Color(0xFFF5F6F8),
                    iconColor: Colors.black87,
                    onTap: _addPostToStory,
                  ),
                  _ShareActionIcon(
                    imageAsset: 'assets/share_icons/instagram.png',
                    label: 'Instagram',
                    backgroundColor: Colors.transparent,
                    iconColor: Colors.white,
                    onTap: _shareInstagram,
                  ),
                  _ShareActionIcon(
                    imageAsset: 'assets/share_icons/whatsapp.png',
                    label: 'WhatsApp',
                    backgroundColor: Colors.transparent,
                    iconColor: Colors.black,
                    onTap: _shareWhatsApp,
                  ),
                  _ShareActionIcon(
                    imageAsset: 'assets/share_icons/threads.png',
                    label: 'Threads',
                    backgroundColor: Colors.transparent,
                    iconColor: Colors.black,
                    onTap: _shareThreads,
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
    required this.lastActiveAt,
  });

  final String id;
  final String name;
  final String? avatarUrl;
  final DateTime? lastActiveAt;
}

class _ShareActionIcon extends StatelessWidget {
  const _ShareActionIcon({
    this.icon,
    this.imageAsset,
    required this.label,
    required this.onTap,
    required this.backgroundColor,
    required this.iconColor,
  });

  final IconData? icon;
  final String? imageAsset;
  final String label;
  final Future<void> Function() onTap;
  final Color backgroundColor;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(32),
      onTap: onTap,
      child: SizedBox(
        width: 78,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: backgroundColor,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: imageAsset != null
                    ? ClipOval(
                        child: Image.asset(
                          imageAsset!,
                          width: 52,
                          height: 52,
                          fit: BoxFit.cover,
                        ),
                      )
                    : Icon(icon, size: 25, color: iconColor),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
