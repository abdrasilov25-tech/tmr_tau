import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart' show ShareParams, SharePlus;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/supabase_constants.dart';
import '../../../../core/router/go_router_pop_safe.dart';
import '../../../../core/storage/chat_list_storage.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../data/channel_owner_api.dart';
import '../../data/invite_candidates.dart';
import '../chat_unread_badge_controller.dart';
import '../widgets/channel_invite_user_sheet.dart';

class ChannelPage extends StatefulWidget {
  const ChannelPage({super.key, required this.channelId, required this.title});

  final String channelId;
  final String title;

  @override
  State<ChannelPage> createState() => _ChannelPageState();
}

class _ChannelPageState extends State<ChannelPage> {
  late final SupabaseClient _client;
  String? _currentUserId;
  String? _ownerId;
  String? _channelTitle;
  String? _description;
  bool _signPosts = true;
  bool _showLinkPreview = true;
  bool _silentBroadcast = false;
  int? _subscriberCount;
  bool _metaLoaded = false;

  final TextEditingController _controller = TextEditingController();
  bool _sending = false;
  bool _loadingSub = false;
  bool? _isSubscribed;

  @override
  void initState() {
    super.initState();
    _client = Supabase.instance.client;
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      _currentUserId = authState.user.id;
    }
    _loadChannelMeta().then((_) => _loadSubscription());
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = context.read<AuthBloc>().state;
      if (auth is! AuthAuthenticated) return;
      await context.read<ChatListStorage>().setLastReadAt(
            widget.channelId,
            DateTime.now(),
          );
      if (!mounted) return;
      await context.read<ChatUnreadBadgeController>().refresh();
    });
  }

  bool get _isOwner =>
      _currentUserId != null &&
      _ownerId != null &&
      _currentUserId == _ownerId;

  Future<void> _loadChannelMeta() async {
    try {
      final row = await _client
          .from(SupabaseConstants.userChannelsTable)
          .select(
            'owner_id,title,description,sign_posts,show_link_preview,silent_broadcast,avatar_url',
          )
          .eq('id', widget.channelId)
          .maybeSingle();
      if (!mounted) return;
      if (row == null) {
        setState(() => _metaLoaded = true);
        return;
      }
      setState(() {
        _ownerId = row['owner_id'] as String?;
        _channelTitle = row['title'] as String?;
        _description = row['description'] as String?;
        _signPosts = (row['sign_posts'] as bool?) ?? true;
        _showLinkPreview = (row['show_link_preview'] as bool?) ?? true;
        _silentBroadcast = (row['silent_broadcast'] as bool?) ?? false;
        _metaLoaded = true;
      });
      await _refreshSubscriberCount();
    } catch (e) {
      try {
        final row = await _client
            .from(SupabaseConstants.userChannelsTable)
            .select('owner_id,title')
            .eq('id', widget.channelId)
            .maybeSingle();
        if (!mounted) return;
        if (row != null) {
          setState(() {
            _ownerId = row['owner_id'] as String?;
            _channelTitle = row['title'] as String?;
            _metaLoaded = true;
          });
        } else {
          setState(() => _metaLoaded = true);
        }
        await _refreshSubscriberCount();
      } catch (e) {
        if (mounted) setState(() => _metaLoaded = true);
      }
    }
  }

  Future<void> _refreshSubscriberCount() async {
    try {
      final n = await _client
          .from(SupabaseConstants.channelSubscribersTable)
          .count(CountOption.exact)
          .eq('channel_id', widget.channelId);
      if (mounted) setState(() => _subscriberCount = n);
    } catch (e) {
      if (mounted) setState(() => _subscriberCount = null);
    }
  }

  Future<void> _loadSubscription() async {
    final uid = _currentUserId;
    final oid = _ownerId;
    if (uid == null || oid == null || uid == oid) {
      if (mounted) setState(() => _isSubscribed = false);
      return;
    }
    try {
      final row = await _client
          .from(SupabaseConstants.channelSubscribersTable)
          .select('user_id')
          .eq('channel_id', widget.channelId)
          .eq('user_id', uid)
          .maybeSingle();
      if (mounted) setState(() => _isSubscribed = row != null);
    } catch (e) {
      if (mounted) setState(() => _isSubscribed = false);
    }
  }

  Future<void> _toggleSubscribe() async {
    if (_currentUserId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Войдите, чтобы подписаться на канал')),
      );
      return;
    }
    setState(() => _loadingSub = true);
    try {
      if (_isSubscribed == true) {
        await _client.rpc(
          'channel_unsubscribe',
          params: {'p_channel_id': widget.channelId},
        );
      } else {
        await _client.rpc(
          'channel_subscribe',
          params: {'p_channel_id': widget.channelId},
        );
      }
      await _loadSubscription();
      await _refreshSubscriberCount();
      if (mounted) {
        await context.read<ChatUnreadBadgeController>().refresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingSub = false);
    }
  }

  Future<void> _shareChannel() async {
    final t = _channelTitle ?? widget.title;
    final text =
        'Канал «$t»\nОткройте в приложении: канал id ${widget.channelId}';
    await SharePlus.instance.share(ShareParams(text: text));
  }

  Future<void> _invitePeople() async {
    if (!_isOwner || _currentUserId == null) return;
    try {
      final subsRes = await _client
          .from(SupabaseConstants.channelSubscribersTable)
          .select('user_id')
          .eq('channel_id', widget.channelId);
      final subIds = (subsRes as List)
          .map((e) => (e as Map<String, dynamic>)['user_id'] as String)
          .toSet();
      subIds.add(_currentUserId!);
      if (_ownerId != null) subIds.add(_ownerId!);

      final all = await loadInviteCandidates(_client, _currentUserId!);
      if (!mounted) return;
      final candidates = all.where((u) => !subIds.contains(u.id)).toList();
      final picked = await showChannelInviteUserPicker(
        context,
        candidates: candidates,
        title: 'Пригласить подписчиков',
        confirmLabel: 'Пригласить',
      );
      if (picked == null || picked.isEmpty || !mounted) return;
      await ChannelOwnerApi.inviteUsers(
        _client,
        channelId: widget.channelId,
        userIds: picked,
      );
      await _refreshSubscriberCount();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Приглашения отправлены')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось пригласить: $e')),
        );
      }
    }
  }

  Future<void> _showSettings() async {
    if (!_isOwner || _currentUserId == null) return;
    final titleCtrl = TextEditingController(text: _channelTitle ?? widget.title);
    final descCtrl = TextEditingController(text: _description ?? '');
    var sign = _signPosts;
    var linkPrev = _showLinkPreview;
    var silent = _silentBroadcast;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: StatefulBuilder(
            builder: (ctx, setSheet) {
              return SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Настройки канала',
                        style: Theme.of(ctx).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: titleCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Название',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descCtrl,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Описание',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Подпись к постам'),
                        value: sign,
                        onChanged: (v) => setSheet(() => sign = v),
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Превью ссылок'),
                        value: linkPrev,
                        onChanged: (v) => setSheet(() => linkPrev = v),
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Тихий режим'),
                        subtitle: const Text(
                          'Меньше навязчивых уведомлений о постах',
                        ),
                        value: silent,
                        onChanged: (v) => setSheet(() => silent = v),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Сохранить'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
    try {
      if (ok == true && mounted) {
        await ChannelOwnerApi.updateChannelSettings(
          _client,
          channelId: widget.channelId,
          ownerId: _currentUserId!,
          title: titleCtrl.text.trim(),
          description: descCtrl.text.trim(),
          signPosts: sign,
          showLinkPreview: linkPrev,
          silentBroadcast: silent,
        );
        await _loadChannelMeta();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Сохранено')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      titleCtrl.dispose();
      descCtrl.dispose();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canPost => _isOwner;

  bool get _showSubscribeBar =>
      _currentUserId != null &&
      _ownerId != null &&
      _currentUserId != _ownerId;

  String get _displayTitle => _channelTitle ?? widget.title;

  Stream<List<Map<String, dynamic>>> _messagesStream() {
    return _client
        .from(SupabaseConstants.channelMessagesTable)
        .stream(primaryKey: ['id'])
        .eq('channel_id', widget.channelId)
        .order('created_at', ascending: true)
        .map((list) => list.cast<Map<String, dynamic>>());
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (!_canPost || text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _client.from(SupabaseConstants.channelMessagesTable).insert({
        'channel_id': widget.channelId,
        'sender_id': _currentUserId,
        'text': text,
        'kind': 'text',
      });
      _controller.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось отправить пост канала: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _systemBubble(String line) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          line,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.grey.shade900,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }

  String _systemLine(String kind, String text) {
    switch (kind) {
      case 'system_subscribe':
        return '$text подписался(ась) на канал';
      case 'system_unsubscribe':
        return '$text отписался(ась) от канала';
      case 'system_invite':
        return '$text приглашён(а) в канал';
      default:
        return text;
    }
  }

  Widget _postBubble(String text) {
    final showSig = _signPosts;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showSig) ...[
            Row(
              children: [
                Icon(Icons.campaign_outlined, size: 16, color: Colors.blue.shade700),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _displayTitle,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue.shade800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          Text(
            text,
            style: const TextStyle(fontSize: 15, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    if (!_metaLoaded) {
      return const SizedBox(
        height: 4,
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    final desc = _description?.trim();
    final sub = _subscriberCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Material(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.campaign_outlined, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _displayTitle,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  if (sub != null)
                    Text(
                      '$sub подписчиков',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                ],
              ),
              if (desc != null && desc.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.35,
                    color: Colors.grey.shade800,
                  ),
                ),
              ],
              if (_isOwner) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (_silentBroadcast)
                      Chip(
                        label: const Text('Тихий режим'),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        labelStyle: const TextStyle(fontSize: 12),
                      ),
                    if (!_showLinkPreview)
                      Chip(
                        label: const Text('Без превью ссылок'),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        labelStyle: const TextStyle(fontSize: 12),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_displayTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.popOrGoHomeChats(),
        ),
        actions: [
          IconButton(
            tooltip: 'Поделиться',
            icon: const Icon(Icons.share_outlined),
            onPressed: _shareChannel,
          ),
          if (_isOwner)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'invite') _invitePeople();
                if (v == 'settings') _showSettings();
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'invite',
                  child: ListTile(
                    leading: Icon(Icons.person_add_outlined),
                    title: Text('Пригласить подписчиков'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'settings',
                  child: ListTile(
                    leading: Icon(Icons.settings_outlined),
                    title: Text('Настройки канала'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _messagesStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    (snapshot.data == null || snapshot.data!.isEmpty)) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const Center(child: Text('Ошибка загрузки канала'));
                }
                final items = snapshot.data ?? const [];
                if (items.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _canPost
                            ? 'Канал готов. Напишите первую публикацию или пригласите людей через меню ⋮'
                            : 'В этом канале пока нет публикаций.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final kind = item['kind'] as String? ?? 'text';
                    final text = (item['text'] as String?) ?? '';
                    if (kind != 'text') {
                      return _systemBubble(_systemLine(kind, text));
                    }
                    return _postBubble(text);
                  },
                );
              },
            ),
          ),
          if (_canPost)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_silentBroadcast)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          'Тихий режим: подписчики получат меньше навязчивых уведомлений.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            minLines: 1,
                            maxLines: 4,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _send(),
                            decoration: InputDecoration(
                              hintText: _showLinkPreview
                                  ? 'Новая публикация канала'
                                  : 'Публикация (превью ссылок выключено в настройках)',
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          onPressed: _sending ? null : _send,
                          icon: _sending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.send),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            )
          else if (_showSubscribeBar)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Только владелец публикует посты. Подпишитесь, чтобы видеть обновления в ленте.',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.tonal(
                      onPressed: _loadingSub ? null : _toggleSubscribe,
                      child: _loadingSub
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              _isSubscribed == true
                                  ? 'Отписаться'
                                  : 'Подписаться',
                            ),
                    ),
                  ],
                ),
              ),
            )
          else if (_currentUserId == null)
            const SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(12, 4, 12, 10),
                child: Text('Войдите, чтобы подписаться на канал.'),
              ),
            )
          else
            const SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(12, 4, 12, 10),
                child: Text('Вы владелец этого канала.'),
              ),
            ),
        ],
      ),
    );
  }
}
