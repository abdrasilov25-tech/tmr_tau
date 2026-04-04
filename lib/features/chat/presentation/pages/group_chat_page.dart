import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:camera/camera.dart';

import '../../../../core/constants/supabase_constants.dart';
import '../../../../core/storage/chat_list_storage.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/city_chat_threads.dart';
import '../../domain/city_chat_moderation_codes.dart';
import '../../domain/temirtau_city_group_config.dart';
import '../city_thread_icons.dart';
import '../widgets/city_chat_fixed_avatar.dart';
import '../chat_unread_badge_controller.dart';
import '../widgets/dm_hold_video_overlay.dart';

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
  late Stream<List<Map<String, dynamic>>> _messages$;
  late Stream<List<Map<String, dynamic>>> _allCityMessages$;
  String? _currentUserId;
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _sending = false;
  bool _recordingVoice = false;
  int _voiceRecordSeconds = 0;
  Timer? _voiceTimer;
  String _groupTitle = '';
  String? _groupAvatarUrl;
  bool _officialCity = false;
  DateTime? _cityBanUntil;
  bool _cityPermanentBan = false;
  String _selectedCityThread = CityChatThreads.defaultThreadId;
  int _lastRenderedMessagesCount = 0;
  bool _wasNearBottom = true;
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _playingAudioMessageId;
  bool _groupRoundVideoOpening = false;

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
    _allCityMessages$ = _allCityMessagesStream();
    _scrollController.addListener(_trackScrollPosition);
    _loadGroupMeta();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final chatStorage = context.read<ChatListStorage>();
      final unreadController = context.read<ChatUnreadBadgeController>();
      final auth = context.read<AuthBloc>().state;
      if (auth is! AuthAuthenticated) return;
      await chatStorage.setLastReadAt(
        widget.groupId,
        DateTime.now(),
      );
      if (_officialCity) {
        await chatStorage.setLastReadAtForGroupThread(
          widget.groupId,
          _selectedCityThread,
          DateTime.now(),
        );
      }
      if (!mounted) return;
      await unreadController.refresh();
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
    _voiceTimer?.cancel();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
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
        'city_thread': CityChatThreads.defaultThreadId,
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

  Stream<List<Map<String, dynamic>>> _allCityMessagesStream() {
    return _client
        .from(SupabaseConstants.chatGroupMessagesTable)
        .stream(primaryKey: ['id'])
        .eq('group_id', widget.groupId)
        .order('created_at', ascending: true)
        .map((list) => list.cast<Map<String, dynamic>>());
  }

  void _changeCityThread(String threadId) {
    if (!_officialCity) return;
    if (_selectedCityThread == threadId) return;
    setState(() {
      _selectedCityThread = threadId;
      _lastRenderedMessagesCount = 0;
      _messages$ = _messagesStream();
    });
    unawaited(
      context.read<ChatListStorage>().setLastReadAtForGroupThread(
        widget.groupId,
        threadId,
        DateTime.now(),
      ),
    );
    unawaited(context.read<ChatUnreadBadgeController>().refresh());
  }

  Future<void> _markSelectedThreadRead(List<Map<String, dynamic>> messages) async {
    if (!_officialCity) return;
    final now = DateTime.now();
    DateTime markAt = now;
    for (final m in messages) {
      final created = DateTime.tryParse((m['created_at'] ?? '').toString());
      if (created != null && created.isAfter(markAt)) {
        markAt = created;
      }
    }
    await context.read<ChatListStorage>().setLastReadAtForGroupThread(
      widget.groupId,
      _selectedCityThread,
      markAt,
    );
    if (!mounted) return;
    await context.read<ChatUnreadBadgeController>().refresh();
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
    final chatStorage = context.read<ChatListStorage>();
    setState(() => _sending = true);
    try {
      await _client.from(SupabaseConstants.chatGroupMessagesTable).insert({
        'group_id': widget.groupId,
        'sender_id': senderId,
        'text': text,
        'kind': 'text',
        if (_officialCity) 'city_thread': _selectedCityThread,
      });
      _controller.clear();
      await chatStorage.setLastReadAtForGroupThread(
        widget.groupId,
        _selectedCityThread,
        DateTime.now(),
      );
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

  Future<void> _startVoiceRecord() async {
    if (_recordingVoice) return;
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted || !mounted) return;
    try {
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/group_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 44100,
          bitRate: 128000,
        ),
        path: path,
      );
      if (!mounted) return;
      setState(() {
        _recordingVoice = true;
        _voiceRecordSeconds = 0;
      });
      _voiceTimer?.cancel();
      _voiceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _voiceRecordSeconds++);
      });
    } on MissingPluginException {
      _showVoicePluginMissing();
    } catch (_) {}
  }

  Future<void> _cancelVoiceRecord() async {
    _voiceTimer?.cancel();
    try {
      await _audioRecorder.stop();
    } on MissingPluginException {
      _showVoicePluginMissing();
      return;
    }
    if (!mounted) return;
    setState(() {
      _recordingVoice = false;
      _voiceRecordSeconds = 0;
    });
  }

  Future<void> _stopAndSendVoice() async {
    if (!_recordingVoice) return;
    _voiceTimer?.cancel();
    String? path;
    try {
      path = await _audioRecorder.stop();
    } on MissingPluginException {
      _showVoicePluginMissing();
      return;
    }
    final secs = _voiceRecordSeconds;
    if (!mounted) return;
    setState(() {
      _recordingVoice = false;
      _voiceRecordSeconds = 0;
    });
    if (path == null || secs < 1) return;
    await _sendVoiceFile(path, secs);
  }

  void _showVoicePluginMissing() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Голосовые временно недоступны на этой сборке приложения'),
      ),
    );
  }

  Future<void> _sendVoiceFile(String localPath, int seconds) async {
    final senderId = _currentUserId;
    if (senderId == null) return;
    final chatStorage = context.read<ChatListStorage>();
    setState(() => _sending = true);
    try {
      final file = File(localPath);
      final ext = localPath.split('.').last;
      final storagePath =
          'group_messages/${widget.groupId}/$senderId/${DateTime.now().millisecondsSinceEpoch}.$ext';
      await _client.storage.from(SupabaseConstants.bucketChatMedia).upload(
            storagePath,
            file,
            fileOptions: const FileOptions(contentType: 'audio/m4a', upsert: false),
          );
      final url = _client.storage
          .from(SupabaseConstants.bucketChatMedia)
          .getPublicUrl(storagePath);
      await _client.from(SupabaseConstants.chatGroupMessagesTable).insert({
        'group_id': widget.groupId,
        'sender_id': senderId,
        'text': 'Голосовое сообщение',
        'kind': 'audio',
        'message_type': 'audio',
        'audio_url': url,
        'duration_seconds': seconds,
        if (_officialCity) 'city_thread': _selectedCityThread,
      });
      await chatStorage.setLastReadAtForGroupThread(
        widget.groupId,
        _selectedCityThread,
        DateTime.now(),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e is StorageException &&
              e.message.toLowerCase().contains('bucket')
          ? 'Хранилище чата не настроено (нужен бакет messages в Supabase).'
          : 'Не удалось отправить аудио. Проверьте соединение.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(msg),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  static String _videoMimeFromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.3gp')) return 'video/3gpp';
    return 'video/mp4';
  }

  Future<void> _pickAndSendRoundVideo() async {
    final senderId = _currentUserId;
    if (senderId == null || _sending || _groupRoundVideoOpening) return;
    final chatStorage = context.read<ChatListStorage>();

    var cam = await Permission.camera.status;
    if (!cam.isGranted) cam = await Permission.camera.request();
    var mic = await Permission.microphone.status;
    if (!mic.isGranted) mic = await Permission.microphone.request();
    if (!cam.isGranted || !mic.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Нужны камера и микрофон для видеокружка'),
          ),
        );
      }
      return;
    }

    final cams = await availableCameras();
    if (cams.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Камера недоступна (например, на симуляторе без камеры)'),
        ),
      );
      return;
    }

    if (!mounted) return;
    _groupRoundVideoOpening = true;
    DmHoldVideoResult? recorded;
    try {
      recorded = await Navigator.of(context).push<DmHoldVideoResult>(
        PageRouteBuilder<DmHoldVideoResult>(
          opaque: false,
          barrierDismissible: false,
          barrierColor: Colors.transparent,
          transitionDuration: const Duration(milliseconds: 220),
          pageBuilder: (context, animation, secondaryAnimation) =>
              const DmHoldVideoOverlay(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    } finally {
      _groupRoundVideoOpening = false;
    }

    if (recorded == null || !mounted) return;

    setState(() => _sending = true);
    try {
      final file = recorded.file;
      int durationSec = 0;
      try {
        final ctrl = VideoPlayerController.file(file);
        await ctrl.initialize();
        durationSec = ctrl.value.duration.inSeconds;
        await ctrl.dispose();
      } catch (_) {}

      final p = file.path;
      final dot = p.lastIndexOf('.');
      final ext = (dot > 0 && dot < p.length - 1)
          ? p.substring(dot + 1).toLowerCase()
          : 'mp4';
      final mime = _videoMimeFromPath(p);
      final storagePath =
          'group_messages/${widget.groupId}/$senderId/${DateTime.now().millisecondsSinceEpoch}.$ext';
      await _client.storage.from(SupabaseConstants.bucketChatMedia).upload(
            storagePath,
            file,
            fileOptions: FileOptions(contentType: mime, upsert: false),
          );
      final url = _client.storage
          .from(SupabaseConstants.bucketChatMedia)
          .getPublicUrl(storagePath);
      await _client.from(SupabaseConstants.chatGroupMessagesTable).insert({
        'group_id': widget.groupId,
        'sender_id': senderId,
        'text': 'Кружок',
        'kind': 'video_circle',
        'message_type': 'video_circle',
        'video_url': url,
        'duration_seconds': durationSec,
        if (_officialCity) 'city_thread': _selectedCityThread,
      });
      await chatStorage.setLastReadAtForGroupThread(
        widget.groupId,
        _selectedCityThread,
        DateTime.now(),
      );
      try {
        await file.delete();
      } catch (_) {}
    } catch (e) {
      if (!mounted) return;
      final msg = e is StorageException &&
              e.message.toLowerCase().contains('bucket')
          ? 'Хранилище чата не настроено (бакет messages).'
          : 'Не удалось отправить кружок. Проверьте соединение.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(msg),
        ),
      );
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
                    const CityChatFixedAvatar(radius: 56),
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
                  ? const CityChatFixedAvatar(radius: 14)
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
          if (_officialCity)
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: _allCityMessages$,
              builder: (context, snapshot) {
                final allMessages = snapshot.data ?? const <Map<String, dynamic>>[];
                final unreadByThread = <String, int>{};
                final storage = context.read<ChatListStorage>();
                for (final t in CityChatThreads.all) {
                  unreadByThread[t.id] = 0;
                }
                for (final m in allMessages) {
                  if (m['sender_id'] == _currentUserId) continue;
                  final thread = (m['city_thread'] as String?)?.trim();
                  final threadId = CityChatThreads.normalizeThreadId(thread);
                  final lastRead = storage.getLastReadAtForGroupThread(
                    widget.groupId,
                    threadId,
                  );
                  final createdAt =
                      DateTime.tryParse((m['created_at'] ?? '').toString());
                  if (createdAt == null) continue;
                  if (lastRead == null || createdAt.isAfter(lastRead)) {
                    unreadByThread[threadId] =
                        (unreadByThread[threadId] ?? 0) + 1;
                  }
                }
                return _CityThreadTabs(
                  selectedId: _selectedCityThread,
                  unreadByThread: unreadByThread,
                  onSelect: _changeCityThread,
                );
              },
            ),
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
                final rawMessages = snapshot.data ?? const <Map<String, dynamic>>[];
                final messages = _officialCity
                    ? rawMessages.where((m) {
                        final thread = (m['city_thread'] as String?)?.trim();
                        final normalized =
                            CityChatThreads.normalizeThreadId(thread);
                        return normalized == _selectedCityThread;
                      }).toList(growable: false)
                    : rawMessages;
                if (_officialCity && messages.isNotEmpty) {
                  unawaited(_markSelectedThreadRead(messages));
                }
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
                    final msgType =
                        (m['message_type'] as String?)?.trim().toLowerCase() ??
                            kind;
                    final text = (m['text'] as String?) ?? '';
                    final messageId = (m['id'] as String?) ?? 'g_$index';
                    final audioUrl = m['audio_url'] as String?;
                    final videoUrl = m['video_url'] as String?;
                    final durationSeconds = (m['duration_seconds'] as num?)?.toInt();
                    if (kind == TemirtauCityGroupConfig.messageKindCityRules) {
                      return _CityRulesMessageBubble(text: text);
                    }
                    if (msgType == 'audio' && audioUrl != null) {
                      final isMe = m['sender_id'] == _currentUserId;
                      return _GroupAudioBubble(
                        key: ValueKey('group_audio_$messageId'),
                        isMe: isMe,
                        audioUrl: audioUrl,
                        durationSeconds: durationSeconds,
                        isPlaying: _playingAudioMessageId == messageId,
                        onPlayPause: () async {
                          try {
                            if (_playingAudioMessageId == messageId) {
                              await _audioPlayer.stop();
                              if (!mounted) return;
                              setState(() => _playingAudioMessageId = null);
                              return;
                            }
                            await _audioPlayer.stop();
                            await _audioPlayer.play(UrlSource(audioUrl));
                            if (!mounted) return;
                            setState(() => _playingAudioMessageId = messageId);
                          } catch (_) {}
                        },
                      );
                    }
                    if (msgType == 'video_circle' && videoUrl != null) {
                      return _GroupVideoCircleBubble(
                        key: ValueKey('group_video_$messageId'),
                        videoUrl: videoUrl,
                      );
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_recordingVoice)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1F2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.mic_rounded, color: Colors.redAccent),
                          const SizedBox(width: 8),
                          Text(
                            'Запись: ${_voiceRecordSeconds ~/ 60}:${(_voiceRecordSeconds % 60).toString().padLeft(2, '0')}',
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: _cancelVoiceRecord,
                            child: const Text('Отмена'),
                          ),
                        ],
                      ),
                    ),
                  Row(
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
                                : (_officialCity
                                      ? 'Сообщение в «${CityChatThreads.metaFor(_selectedCityThread).label}»'
                                      : 'Сообщение в группу'),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed:
                            _sending || _cityPostingBlocked ? null : _pickAndSendRoundVideo,
                        icon: const Icon(Icons.videocam_rounded),
                      ),
                      Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (_) {
                          if (_sending || _cityPostingBlocked) return;
                          unawaited(_startVoiceRecord());
                        },
                        onPointerUp: (_) {
                          if (_sending || _cityPostingBlocked) return;
                          unawaited(_stopAndSendVoice());
                        },
                        onPointerCancel: (_) {
                          if (_sending || _cityPostingBlocked) return;
                          unawaited(_cancelVoiceRecord());
                        },
                        child: CircleAvatar(
                          radius: 20,
                          backgroundColor:
                              _recordingVoice ? Colors.redAccent : Colors.grey.shade800,
                          child: Icon(
                            _recordingVoice
                                ? Icons.mic_rounded
                                : Icons.mic_none_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed:
                            _sending || _cityPostingBlocked ? null : _sendMessage,
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
          ),
        ],
      ),
    );
  }
}

class _GroupAudioBubble extends StatelessWidget {
  const _GroupAudioBubble({
    super.key,
    required this.isMe,
    required this.audioUrl,
    required this.durationSeconds,
    required this.isPlaying,
    required this.onPlayPause,
  });

  final bool isMe;
  final String audioUrl;
  final int? durationSeconds;
  final bool isPlaying;
  final VoidCallback onPlayPause;

  @override
  Widget build(BuildContext context) {
    final bg = isMe ? Theme.of(context).colorScheme.primary : Colors.grey.shade200;
    final fg = isMe ? Colors.white : Colors.black87;
    final d = durationSeconds ?? 0;
    final mm = (d ~/ 60).toString().padLeft(2, '0');
    final ss = (d % 60).toString().padLeft(2, '0');
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: onPlayPause,
              icon: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: fg,
              ),
            ),
            Text(
              d > 0 ? '$mm:$ss' : 'аудио',
              style: TextStyle(color: fg, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupVideoCircleBubble extends StatefulWidget {
  const _GroupVideoCircleBubble({
    super.key,
    required this.videoUrl,
  });

  final String videoUrl;

  @override
  State<_GroupVideoCircleBubble> createState() => _GroupVideoCircleBubbleState();
}

class _GroupVideoCircleBubbleState extends State<_GroupVideoCircleBubble> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    final uri = Uri.tryParse(widget.videoUrl);
    if (uri == null) return;
    final c = VideoPlayerController.networkUrl(uri);
    _controller = c;
    c.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: GestureDetector(
          onTap: () {
            if (c == null || !c.value.isInitialized) return;
            if (c.value.isPlaying) {
              c.pause();
            } else {
              c.play();
            }
            setState(() {});
          },
          child: ClipOval(
            child: SizedBox(
              width: 160,
              height: 160,
              child: c != null && c.value.isInitialized
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: c.value.size.width,
                            height: c.value.size.height,
                            child: VideoPlayer(c),
                          ),
                        ),
                        if (!c.value.isPlaying)
                          const Center(
                            child: Icon(
                              Icons.play_arrow_rounded,
                              size: 44,
                              color: Colors.white,
                            ),
                          ),
                      ],
                    )
                  : Container(
                      color: Colors.black12,
                      alignment: Alignment.center,
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    ),
            ),
          ),
        ),
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

class _CityThreadTabs extends StatelessWidget {
  const _CityThreadTabs({
    required this.selectedId,
    required this.unreadByThread,
    required this.onSelect,
  });

  final String selectedId;
  final Map<String, int> unreadByThread;
  final ValueChanged<String> onSelect;

  Widget _threadLeadingGraphic(CityChatThread t, Color accent) {
    final asset = t.avatarAsset;
    if (asset != null) {
      return Container(
        width: 36,
        height: 36,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.asset(
            asset,
            fit: BoxFit.cover,
            alignment: Alignment.center,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        cityThreadMaterialIcon(t.iconKey),
        color: accent,
        size: 22,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: SizedBox(
        height: 120,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          itemCount: CityChatThreads.all.length,
          separatorBuilder: (context, i) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final t = CityChatThreads.all[index];
            final selected = selectedId == t.id;
            final accent = cityThreadAccentColor(t.iconKey);
            final unread = unreadByThread[t.id] ?? 0;
            return Badge(
              isLabelVisible: unread > 0,
              label: Text(
                unread > 99 ? '99+' : '$unread',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => onSelect(t.id),
                  borderRadius: BorderRadius.circular(16),
                  child: Ink(
                    width: 136,
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: selected ? accent : scheme.outlineVariant,
                        width: selected ? 2 : 1,
                      ),
                      color: selected
                          ? accent.withValues(alpha: 0.1)
                          : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _threadLeadingGraphic(t, accent),
                        const SizedBox(height: 8),
                        Text(
                          t.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                letterSpacing: -0.2,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          t.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontSize: 10,
                                height: 1.28,
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
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
