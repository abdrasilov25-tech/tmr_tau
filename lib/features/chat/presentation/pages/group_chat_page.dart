import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/supabase_constants.dart';
import '../../../../core/storage/chat_list_storage.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/city_chat_moderation_codes.dart';
import '../../domain/temirtau_city_group_config.dart';
import '../chat_unread_badge_controller.dart';

class GroupChatPage extends StatefulWidget {
  const GroupChatPage({
    super.key,
    required this.groupId,
    required this.groupName,
    this.officialCityChat = false,
  });

  final String groupId;
  final String groupName;

  /// Подсказка из списка чатов: официальный городской чат без лишнего запроса.
  final bool officialCityChat;

  @override
  State<GroupChatPage> createState() => _GroupChatPageState();
}

class _GroupChatPageState extends State<GroupChatPage> {
  late final SupabaseClient _client;
  late final Stream<List<Map<String, dynamic>>> _messages$;
  String? _currentUserId;
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _sending = false;
  String _groupTitle = '';
  String? _groupAvatarUrl;
  bool _officialCity = false;
  DateTime? _cityBanUntil;
  bool _cityPermanentBan = false;
  int _lastRenderedMessagesCount = 0;
  bool _wasNearBottom = true;

  @override
  void initState() {
    super.initState();
    _client = Supabase.instance.client;
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      _currentUserId = authState.user.id;
    }
    _groupTitle = widget.groupName;
    _officialCity =
        widget.officialCityChat ||
        TemirtauCityGroupConfig.isOfficialCityChatTitle(widget.groupName);
    _messages$ = _messagesStream();
    _scrollController.addListener(_trackScrollPosition);
    _loadGroupMeta();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = context.read<AuthBloc>().state;
      if (auth is! AuthAuthenticated) return;
      await context.read<ChatListStorage>().setLastReadAt(
        widget.groupId,
        DateTime.now(),
      );
      if (!mounted) return;
      await context.read<ChatUnreadBadgeController>().refresh();
      await _maybeInsertFirstVisitCityRules();
      if (!mounted) return;
      if (_officialCity) await _refreshCityModeration();
    });
  }

  bool get _cityPostingBlocked {
    if (!_officialCity) return false;
    if (_cityPermanentBan) return true;
    final u = _cityBanUntil;
    if (u == null) return false;
    return u.isAfter(DateTime.now());
  }

  Future<void> _refreshCityModeration() async {
    if (!_officialCity) return;
    final uid = _currentUserId;
    if (uid == null) return;
    try {
      final row = await _client
          .from(SupabaseConstants.cityChatUserModerationTable)
          .select('banned_until,permanent_ban')
          .eq('user_id', uid)
          .maybeSingle();
      if (!mounted) return;
      DateTime? until;
      if (row != null && row['banned_until'] != null) {
        until = DateTime.tryParse(row['banned_until'].toString());
      }
      setState(() {
        _cityBanUntil = until;
        _cityPermanentBan = row?['permanent_ban'] == true;
      });
    } catch (_) {
      // Таблица ещё не создана — игнорируем.
    }
  }

  void _showCityModerationFeedback(String rawError) {
    if (!mounted) return;
    final text = CityChatModerationCodes.userMessageFor(rawError);
    if (text.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.removeListener(_trackScrollPosition);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _trackScrollPosition() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    // Keep a small threshold so we auto-scroll only when user is reading latest messages.
    _wasNearBottom = (pos.maxScrollExtent - pos.pixels) <= 120;
  }

  void _scheduleAutoScrollIfNeeded(int messagesCount) {
    final hasNewMessages = messagesCount > _lastRenderedMessagesCount;
    _lastRenderedMessagesCount = messagesCount;
    if (!hasNewMessages) return;
    if (!_wasNearBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final pos = _scrollController.position;
      _scrollController.animateTo(
        pos.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _maybeInsertFirstVisitCityRules() async {
    if (!_officialCity) return;
    final storage = context.read<ChatListStorage>();
    if (storage.hasSeenCityChatRules(widget.groupId)) return;
    final uid = _currentUserId;
    if (uid == null) return;
    try {
      await _client.from(SupabaseConstants.chatGroupMessagesTable).insert({
        'group_id': widget.groupId,
        'sender_id': uid,
        'text': TemirtauCityGroupConfig.firstVisitRulesMessage,
        'kind': TemirtauCityGroupConfig.messageKindCityRules,
      });
      await storage.setSeenCityChatRules(widget.groupId);
    } catch (_) {
      // Колонка kind / RLS — повторим при следующем входе.
    }
  }

  Stream<List<Map<String, dynamic>>> _messagesStream() {
    return _client
        .from(SupabaseConstants.chatGroupMessagesTable)
        .stream(primaryKey: ['id'])
        .eq('group_id', widget.groupId)
        .order('created_at', ascending: true)
        .map((list) => list.cast<Map<String, dynamic>>());
  }

  Future<void> _loadGroupMeta() async {
    try {
      final row = await _client
          .from(SupabaseConstants.chatGroupsTable)
          .select('title,avatar_url,is_official_city_chat')
          .eq('id', widget.groupId)
          .maybeSingle();
      if (row == null || !mounted) return;
      final title = (row['title'] as String?) ?? widget.groupName;
      final fromFlag = row['is_official_city_chat'] == true;
      final fromTitle = TemirtauCityGroupConfig.isOfficialCityChatTitle(title);
      final isCity = fromFlag || fromTitle || widget.officialCityChat;
      setState(() {
        _groupTitle = title;
        _groupAvatarUrl = row['avatar_url'] as String?;
        _officialCity = isCity;
      });
      if (isCity) await _refreshCityModeration();
    } catch (_) {
      if (mounted) {
        final isCity =
            widget.officialCityChat ||
            TemirtauCityGroupConfig.isOfficialCityChatTitle(_groupTitle);
        setState(() {
          _officialCity = isCity;
        });
        if (isCity) await _refreshCityModeration();
      }
    }
  }

  Future<void> _openGroupInfo() async {
    final left = await context.push(
      '/chat-group/${widget.groupId}/info?city=${_officialCity ? '1' : '0'}',
    );
    if (!mounted) return;
    if (left == true) {
      context.pop();
      return;
    }
    await _loadGroupMeta();
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    final senderId = _currentUserId;
    if (text.isEmpty || senderId == null || _sending) return;
    if (_officialCity && _cityPostingBlocked) return;
    setState(() => _sending = true);
    try {
      await _client.from(SupabaseConstants.chatGroupMessagesTable).insert({
        'group_id': widget.groupId,
        'sender_id': senderId,
        'text': text,
        'kind': 'text',
      });
      _controller.clear();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      final blob = '${e.message} ${e.details ?? ''} ${e.hint ?? ''}';
      if (CityChatModerationCodes.isModerationCode(blob)) {
        _showCityModerationFeedback(blob);
        await _refreshCityModeration();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось отправить: ${e.message}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      final s = e.toString();
      if (CityChatModerationCodes.isModerationCode(s)) {
        _showCityModerationFeedback(s);
        await _refreshCityModeration();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Не удалось отправить: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_groupTitle),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: _officialCity
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Theme.of(context)
                            .colorScheme
                            .primaryContainer
                            .withValues(alpha: 0.5),
                      ),
                      child: Icon(
                        Icons.location_city_rounded,
                        size: 52,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      TemirtauCityGroupConfig.title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Войдите в аккаунт, чтобы читать переписку и писать в городском чате.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Colors.grey.shade700,
                            height: 1.35,
                          ),
                    ),
                    const SizedBox(height: 28),
                    FilledButton.icon(
                      onPressed: () => context.push('/login'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                        shape: const StadiumBorder(),
                      ),
                      icon: const Icon(Icons.login_rounded),
                      label: const Text('Войти'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => context.push('/register'),
                      child: const Text('Создать аккаунт'),
                    ),
                  ],
                ),
              )
            : const Center(
                child: Text('Войдите, чтобы открыть групповой чат'),
              ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: _openGroupInfo,
          borderRadius: BorderRadius.circular(10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _officialCity
                  ? const _CityChatAvatarPlaceholder()
                  : CachedAvatar(
                      imageUrl: _groupAvatarUrl,
                      radius: 14,
                      fallbackText: _groupTitle,
                    ),
              const SizedBox(width: 8),
              Flexible(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        _groupTitle,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (_officialCity) ...[
                      const SizedBox(width: 6),
                      const _CityAppBarBadge(),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          if (_officialCity) const _PinnedCommunityBanner(),
          if (_officialCity && _cityPostingBlocked)
            _CityChatBlockedBar(
              permanent: _cityPermanentBan,
              bannedUntil: _cityBanUntil,
            ),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _messages$,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const Center(child: Text('Ошибка загрузки сообщений'));
                }
                final messages = snapshot.data ?? const [];
                if (messages.isEmpty) {
                  _lastRenderedMessagesCount = 0;
                  return Center(
                    child: Text(
                      _officialCity
                          ? 'Напишите первое сообщение соседям.'
                          : 'Групповой чат создан. Напишите сообщение.',
                    ),
                  );
                }
                _scheduleAutoScrollIfNeeded(messages.length);
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final m = messages[index];
                    final kind = m['kind'] as String? ?? 'text';
                    final text = (m['text'] as String?) ?? '';
                    if (kind == TemirtauCityGroupConfig.messageKindCityRules) {
                      return _CityRulesMessageBubble(text: text);
                    }
                    if (kind != 'text') {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Center(
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 320),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              text,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey.shade900,
                                fontSize: 12.5,
                                height: 1.25,
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                    final isMe = m['sender_id'] == _currentUserId;
                    return Align(
                      alignment: isMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isMe
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          text,
                          style: TextStyle(
                            color: isMe ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      readOnly: _cityPostingBlocked,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: InputDecoration(
                        hintText: _cityPostingBlocked
                            ? 'Отправка временно недоступна'
                            : 'Сообщение в группу',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending || _cityPostingBlocked
                        ? null
                        : _sendMessage,
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
            ),
          ),
        ],
      ),
    );
  }
}

class _CityChatBlockedBar extends StatelessWidget {
  const _CityChatBlockedBar({
    required this.permanent,
    required this.bannedUntil,
  });

  final bool permanent;
  final DateTime? bannedUntil;

  String _untilLine() {
    if (permanent) return 'Отправка сообщений в этот чат отключена навсегда.';
    final u = bannedUntil;
    if (u == null || !u.isAfter(DateTime.now())) {
      return 'Попробуйте отправить сообщение снова.';
    }
    final d = u.toLocal();
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    return 'Снова можно будет писать после $dd.$mm.${d.year} $hh:$min.';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Material(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.gavel_rounded,
                color: Colors.orange.shade800,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      permanent
                          ? 'Блокировка городского чата'
                          : 'Ограничение модерации',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.orange.shade900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _untilLine(),
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CityAppBarBadge extends StatelessWidget {
  const _CityAppBarBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'CITY',
        style: TextStyle(
          color: scheme.onPrimary,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _CityChatAvatarPlaceholder extends StatelessWidget {
  const _CityChatAvatarPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: <Color>[Color(0xFF0284C7), Color(0xFF38BDF8)],
        ),
      ),
      child: const Icon(
        Icons.location_city_rounded,
        color: Colors.white,
        size: 16,
      ),
    );
  }
}

/// Закреплённый блок «о сообществе» вверху городского чата.
class _PinnedCommunityBanner extends StatelessWidget {
  const _PinnedCommunityBanner();

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Material(
        elevation: 2,
        shadowColor: const Color(0xFF0EA5E9).withValues(alpha: 0.35),
        borderRadius: radius,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                Color(0xFF0369A1),
                Color(0xFF0284C7),
                Color(0xFF0EA5E9),
              ],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.groups_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'О сообществе',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              letterSpacing: -0.2,
                            ),
                          ),
                          Text(
                            TemirtauCityGroupConfig.listSubtitle,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'CITY',
                        style: TextStyle(
                          color: Color(0xFF0369A1),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  TemirtauCityGroupConfig.communityDescription,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.95),
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  TemirtauCityGroupConfig.pinnedAboutBody,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Карточка правил при первом входе (kind = city_rules).
class _CityRulesMessageBubble extends StatelessWidget {
  const _CityRulesMessageBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  Theme.of(
                    context,
                  ).colorScheme.primaryContainer.withValues(alpha: 0.95),
                  const Color(0xFFE0F2FE),
                ],
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.18),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.22),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        color: Theme.of(context).colorScheme.primary,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Правила Temirtau city',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: Theme.of(context).colorScheme.primary,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'CITY',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    text,
                    style: TextStyle(
                      fontSize: 13.2,
                      height: 1.45,
                      color: Colors.grey.shade900.withValues(alpha: 0.92),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
