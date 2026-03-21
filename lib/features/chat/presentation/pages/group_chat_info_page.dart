import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/supabase_constants.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';

class GroupChatInfoPage extends StatefulWidget {
  const GroupChatInfoPage({
    super.key,
    required this.groupId,
  });

  final String groupId;

  @override
  State<GroupChatInfoPage> createState() => _GroupChatInfoPageState();
}

class _GroupChatInfoPageState extends State<GroupChatInfoPage> {
  late final SupabaseClient _client;
  String? _currentUserId;
  bool _loading = true;
  bool _saving = false;
  Map<String, dynamic>? _group;
  List<_GroupMemberItem> _members = const [];

  bool get _isOwner =>
      _group != null && _group!['owner_id'] == _currentUserId;

  @override
  void initState() {
    super.initState();
    _client = Supabase.instance.client;
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      _currentUserId = authState.user.id;
    }
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final groupRes = await _client
          .from(SupabaseConstants.chatGroupsTable)
          .select('id,owner_id,title,description,avatar_url,created_at')
          .eq('id', widget.groupId)
          .maybeSingle();
      if (groupRes == null) {
        if (!mounted) return;
        Navigator.pop(context);
        return;
      }
      final membersRes = await _client
          .from(SupabaseConstants.chatGroupMembersTable)
          .select('user_id')
          .eq('group_id', widget.groupId);
      final memberIds = (membersRes as List)
          .map((e) => (e as Map<String, dynamic>)['user_id'] as String?)
          .whereType<String>()
          .toList(growable: false);
      List<_GroupMemberItem> items = const [];
      if (memberIds.isNotEmpty) {
        final usersRes = await _client
            .from(SupabaseConstants.usersTable)
            .select('id,name,avatar')
            .inFilter('id', memberIds);
        final users = (usersRes as List).cast<Map<String, dynamic>>();
        final userMap = <String, Map<String, dynamic>>{
          for (final u in users) u['id'] as String: u,
        };
        items = memberIds.map((id) {
          final u = userMap[id];
          return _GroupMemberItem(
            id: id,
            name: (u?['name'] as String?) ?? 'Пользователь',
            avatarUrl: u?['avatar'] as String?,
          );
        }).toList(growable: false);
      }
      if (!mounted) return;
      setState(() {
        _group = groupRes;
        _members = items;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось загрузить группу: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editTitleAndDescription() async {
    final group = _group;
    if (!_isOwner || group == null) return;
    final titleController = TextEditingController(
      text: (group['title'] as String?) ?? '',
    );
    final descController = TextEditingController(
      text: (group['description'] as String?) ?? '',
    );
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final media = MediaQuery.of(ctx);
        return AnimatedPadding(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Название группы'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Описание'),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Сохранить'),
                ),
              ],
            ),
          ),
        );
      },
    );
    final title = titleController.text.trim();
    final description = descController.text.trim();
    titleController.dispose();
    descController.dispose();
    if (ok != true || title.isEmpty) return;
    setState(() => _saving = true);
    try {
      await _client.from(SupabaseConstants.chatGroupsTable).update({
        'title': title,
        'description': description,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', widget.groupId);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось обновить группу: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changeAvatar() async {
    if (!_isOwner) return;
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() => _saving = true);
    try {
      final file = File(picked.path);
      final ext = file.path.split('.').last;
      final fileName =
          'group_${widget.groupId}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final storage = _client.storage.from(SupabaseConstants.bucketAvatars);
      await storage.upload(
        fileName,
        file,
        fileOptions: const FileOptions(upsert: true),
      );
      final publicUrl = storage.getPublicUrl(fileName);
      await _client.from(SupabaseConstants.chatGroupsTable).update({
        'avatar_url': publicUrl,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', widget.groupId);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось обновить аватар: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addMember() async {
    if (!_isOwner) return;
    final memberIds = _members.map((e) => e.id).toSet();
    final current = _currentUserId;
    if (current == null) return;
    try {
      final myFollowingRes = await _client
          .from(SupabaseConstants.followersTable)
          .select('following_id')
          .eq('follower_id', current);
      final myFollowersRes = await _client
          .from(SupabaseConstants.followersTable)
          .select('follower_id')
          .eq('following_id', current);
      final followingIds = (myFollowingRes as List)
          .map((e) => (e as Map<String, dynamic>)['following_id'] as String?)
          .whereType<String>()
          .toSet();
      final followerIds = (myFollowersRes as List)
          .map((e) => (e as Map<String, dynamic>)['follower_id'] as String?)
          .whereType<String>()
          .toSet();
      final candidates = followingIds
          .intersection(followerIds)
          .where((id) => !memberIds.contains(id))
          .toList(growable: false);
      if (candidates.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет доступных пользователей для добавления')),
        );
        return;
      }
      final usersRes = await _client
          .from(SupabaseConstants.usersTable)
          .select('id,name,avatar')
          .inFilter('id', candidates)
          .order('name');
      if (!mounted) return;
      final users = (usersRes as List).cast<Map<String, dynamic>>();
      String? pickedId;
      await showModalBottomSheet<void>(
        context: context,
        builder: (ctx) {
          return SafeArea(
            child: ListView.builder(
              itemCount: users.length,
              itemBuilder: (_, i) {
                final u = users[i];
                return ListTile(
                  leading: CachedAvatar(
                    imageUrl: u['avatar'] as String?,
                    radius: 18,
                    fallbackText: (u['name'] as String?) ?? 'Пользователь',
                  ),
                  title: Text((u['name'] as String?) ?? 'Пользователь'),
                  onTap: () {
                    pickedId = u['id'] as String?;
                    Navigator.pop(ctx);
                  },
                );
              },
            ),
          );
        },
      );
      if (pickedId == null) return;
      await _client.from(SupabaseConstants.chatGroupMembersTable).insert({
        'group_id': widget.groupId,
        'user_id': pickedId!,
      });
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось добавить участника: $e')),
      );
    }
  }

  Future<void> _removeMember(String userId) async {
    if (!_isOwner) return;
    await _client
        .from(SupabaseConstants.chatGroupMembersTable)
        .delete()
        .eq('group_id', widget.groupId)
        .eq('user_id', userId);
    await _load();
  }

  Future<void> _leaveGroup() async {
    final current = _currentUserId;
    if (current == null) return;
    await _client
        .from(SupabaseConstants.chatGroupMembersTable)
        .delete()
        .eq('group_id', widget.groupId)
        .eq('user_id', current);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final group = _group;
    if (group == null) {
      return const Scaffold(body: Center(child: Text('Группа не найдена')));
    }
    final title = (group['title'] as String?) ?? 'Групповой чат';
    final desc = (group['description'] as String?) ?? '';
    final avatar = (group['avatar_url'] as String?) ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Информация о группе'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: GestureDetector(
              onTap: _isOwner ? _changeAvatar : null,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CachedAvatar(
                    imageUrl: avatar.isEmpty ? null : avatar,
                    radius: 42,
                    fallbackText: title,
                  ),
                  if (_isOwner)
                    const CircleAvatar(
                      radius: 14,
                      child: Icon(Icons.edit, size: 16),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              desc,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: 14),
          if (_isOwner) ...[
            FilledButton.icon(
              onPressed: _saving ? null : _editTitleAndDescription,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Изменить название и описание'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _saving ? null : _addMember,
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('Добавить участника'),
            ),
          ] else
            OutlinedButton.icon(
              onPressed: _leaveGroup,
              icon: const Icon(Icons.logout),
              label: const Text('Выйти из группы'),
            ),
          const SizedBox(height: 14),
          Text(
            'Участники (${_members.length})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ..._members.map((m) {
            final canRemove = _isOwner && m.id != _currentUserId;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CachedAvatar(
                imageUrl: m.avatarUrl,
                radius: 18,
                fallbackText: m.name,
              ),
              title: Text(m.name),
              trailing: canRemove
                  ? IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => _removeMember(m.id),
                    )
                  : null,
            );
          }),
        ],
      ),
    );
  }
}

class _GroupMemberItem {
  const _GroupMemberItem({
    required this.id,
    required this.name,
    required this.avatarUrl,
  });

  final String id;
  final String name;
  final String? avatarUrl;
}
