import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/constants/supabase_constants.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../../core/theme/themed_content_surface.dart';
import '../../../../core/storage/chat_list_storage.dart';
import '../chat_unread_badge_controller.dart';
import '../../../../core/theme/theme_decoration_helper.dart';
import '../../../../core/theme/theme_index_notifier.dart';
import '../../../../core/widgets/theme_picker_sheet.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../stories/domain/entities/story_group_entity.dart';
import '../../../stories/domain/repositories/stories_repository.dart';
import '../../../stories/presentation/pages/story_viewer_args.dart';
import '../../../post/domain/repositories/post_repository.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.peerId,
    this.peerName = 'Продавец',
    this.markReadOnOpen = true,
  });

  final String peerId;
  final String peerName;
  /// Если true, при открытии чат помечается прочитанным. Если false — оставляем непрочитанным.
  final bool markReadOnOpen;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  static const String _storyDmPrefix = '__story__';
  static const String _postDmPrefix = '__post__';
  late final SupabaseClient _client;
  final TextEditingController _controller = TextEditingController();
  final ScrollController _messagesScrollController = ScrollController();
  bool _sending = false;
  bool _showScrollToBottom = false;
  bool _showNewMessagesHint = false;
  bool _didInitialAutoScroll = false;
  int _lastMessageCount = 0;
  String? _lastLatestMessageId;
  bool _forceScrollToLatest = false;
  bool _selectionMode = false;
  final Set<String> _selectedMessageIds = <String>{};
  List<Map<String, dynamic>> _latestDialogMessages = const [];

  // Оптимистичные сообщения: показываются сразу, до подтверждения Supabase
  final List<Map<String, dynamic>> _optimisticMessages = [];

  // Панель эмодзи
  bool _showEmojiPanel = false;
  Map<String, List<Map<String, dynamic>>> _reactionsByMessageId = {};
  Timer? _reactionsDebounce;
  Timer? _markReadDebounce;
  Timer? _presenceTimer;

  static const Duration _onlineThreshold = Duration(minutes: 2);
  static const List<String> _quickReactionEmojis = [
    '❤️',
    '👍',
    '😂',
    '😮',
    '😢',
    '🙏',
    '🔥',
    '👏',
  ];

  // ── Голосовые сообщения ────────────────────────────────────
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecordingVoice = false;
  int _voiceRecordSeconds = 0;
  Timer? _voiceTimer;
  // Переключение кнопки send/mic/camera в зависимости от ввода
  final ValueNotifier<bool> _textHasContent = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _client = Supabase.instance.client;
    _presenceTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      unawaited(_pulseOwnPresence());
    });
    unawaited(_pulseOwnPresence());
    if (widget.markReadOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_me() == null) return;
        context
            .read<ChatListStorage>()
            .setLastReadAt(widget.peerId, DateTime.now())
            .then((_) {
          if (!mounted) return;
          context.read<ChatUnreadBadgeController>().refresh();
        });
      });
    }
  }

  /// Актуальный id сессии (после смены аккаунта не остаётся «залипшим» в initState).
  String? _me() {
    final s = context.read<AuthBloc>().state;
    return s is AuthAuthenticated ? s.user.id : null;
  }

  @override
  void deactivate() {
    if (context.mounted) {
      context.read<ChatUnreadBadgeController>().refresh();
    }
    super.deactivate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reactionsDebounce?.cancel();
    _markReadDebounce?.cancel();
    _presenceTimer?.cancel();
    _textHasContent.dispose();
    _voiceTimer?.cancel();
    _audioRecorder.dispose();
    _controller.dispose();
    _messagesScrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_pulseOwnPresence());
    }
  }

  Future<void> _pulseOwnPresence() async {
    final uid = _me();
    if (uid == null) return;
    try {
      await _client.from(SupabaseConstants.usersTable).update({
        'last_active_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', uid);
    } catch (_) {}
  }

  Stream<List<Map<String, dynamic>>> _peerPresenceStream() {
    return _client
        .from(SupabaseConstants.usersTable)
        .stream(primaryKey: ['id'])
        .eq('id', widget.peerId);
  }

  DateTime? _parseTs(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.toUtc();
    return DateTime.tryParse(v.toString())?.toUtc();
  }

  bool _isPeerOnline(DateTime? lastActive) {
    if (lastActive == null) return false;
    return DateTime.now().toUtc().difference(lastActive) < _onlineThreshold;
  }

  String _formatPeerPresenceSubtitle(DateTime? lastActive) {
    if (_isPeerOnline(lastActive)) return 'онлайн';
    if (lastActive == null) return 'давно не заходил';
    final now = DateTime.now();
    final local = lastActive.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(local.year, local.month, local.day);
    String hm(int h, int m) =>
        '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    if (msgDay == today) {
      return 'был(а) в сети сегодня в ${hm(local.hour, local.minute)}';
    }
    if (msgDay == today.subtract(const Duration(days: 1))) {
      return 'был(а) в сети вчера в ${hm(local.hour, local.minute)}';
    }
    return 'был(а) в сети ${local.day.toString().padLeft(2, '0')}.'
        '${local.month.toString().padLeft(2, '0')}.${local.year} '
        '${hm(local.hour, local.minute)}';
  }

  void _scheduleReactionsFetch(List<Map<String, dynamic>> messages) {
    _reactionsDebounce?.cancel();
    _reactionsDebounce = Timer(const Duration(milliseconds: 450), () {
      unawaited(_loadReactionsForMessages(messages));
    });
  }

  Future<void> _loadReactionsForMessages(
    List<Map<String, dynamic>> messages,
  ) async {
    final ids = messages
        .map((m) => (m['id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toList();
    if (ids.isEmpty) {
      if (mounted && _reactionsByMessageId.isNotEmpty) {
        setState(() => _reactionsByMessageId = {});
      }
      return;
    }
    final next = <String, List<Map<String, dynamic>>>{};
    const chunk = 80;
    try {
      for (var i = 0; i < ids.length; i += chunk) {
        final end = i + chunk > ids.length ? ids.length : i + chunk;
        final part = ids.sublist(i, end);
        final rows = await _client
            .from(SupabaseConstants.messageReactionsTable)
            .select()
            .inFilter('message_id', part);
        for (final r in rows) {
          final mid = (r['message_id'] ?? '').toString();
          if (mid.isEmpty) continue;
          next.putIfAbsent(mid, () => []).add(Map<String, dynamic>.from(r));
        }
      }
      if (!mounted) return;
      if (_reactionsMapsEqual(_reactionsByMessageId, next)) return;
      setState(() => _reactionsByMessageId = next);
    } catch (_) {}
  }

  bool _reactionsMapsEqual(
    Map<String, List<Map<String, dynamic>>> a,
    Map<String, List<Map<String, dynamic>>> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      final other = b[e.key];
      if (other == null || other.length != e.value.length) return false;
      for (var i = 0; i < e.value.length; i++) {
        final x = e.value[i];
        final y = other[i];
        if ((x['user_id'] ?? '') != (y['user_id'] ?? '') ||
            (x['emoji'] ?? '') != (y['emoji'] ?? '')) {
          return false;
        }
      }
    }
    return true;
  }

  void _scheduleMarkReadIfVisible() {
    if (!widget.markReadOnOpen) return;
    _markReadDebounce?.cancel();
    _markReadDebounce = Timer(const Duration(milliseconds: 500), () {
      unawaited(_markPeerMessagesRead());
    });
  }

  Future<void> _markPeerMessagesRead() async {
    final me = _me();
    if (me == null || !mounted) return;
    if (!_messagesScrollController.hasClients) return;
    final position = _messagesScrollController.position;
    final distanceFromBottom = position.pixels - position.minScrollExtent;
    if (distanceFromBottom > 200) return;
    try {
      await _client.rpc(
        'mark_dm_messages_read',
        params: {'p_peer_id': widget.peerId},
      );
    } catch (_) {}
  }

  Future<void> _setReactionForMessage(String messageId, String emoji) async {
    final me = _me();
    if (me == null || messageId.isEmpty) return;
    final trimmed = emoji.trim();
    if (trimmed.isEmpty) return;
    try {
      final existing = _reactionsByMessageId[messageId] ?? [];
      Map<String, dynamic>? mine;
      for (final r in existing) {
        if ((r['user_id'] ?? '').toString() == me) {
          mine = r;
          break;
        }
      }
      if (mine != null && (mine['emoji'] ?? '').toString() == trimmed) {
        await _client
            .from(SupabaseConstants.messageReactionsTable)
            .delete()
            .eq('message_id', messageId)
            .eq('user_id', me);
      } else if (mine != null) {
        await _client
            .from(SupabaseConstants.messageReactionsTable)
            .update({'emoji': trimmed})
            .eq('message_id', messageId)
            .eq('user_id', me);
      } else {
        await _client.from(SupabaseConstants.messageReactionsTable).insert({
          'message_id': messageId,
          'user_id': me,
          'emoji': trimmed,
        });
      }
      if (mounted) {
        await _loadReactionsForMessages(_latestDialogMessages);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось поставить реакцию: $e')),
      );
    }
  }

  void _showReactionPickerSheet(String messageId) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Реакция',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _quickReactionEmojis
                    .map(
                      (e) => Material(
                        color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            Navigator.pop(ctx);
                            unawaited(_setReactionForMessage(messageId, e));
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text(e, style: const TextStyle(fontSize: 28)),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openForwardPeerPicker(Map<String, dynamic> message) async {
    final me = _me();
    if (me == null) return;
    final peerIds = await _recentDmPeerIds(excluding: {me, widget.peerId});
    if (!mounted) return;
    if (peerIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет других диалогов для пересылки')),
      );
      return;
    }
    List<Map<String, dynamic>> usersRows = [];
    try {
      usersRows = await _client
          .from(SupabaseConstants.usersTable)
          .select('id, name, avatar')
          .inFilter('id', peerIds);
    } catch (_) {}
    final byId = <String, Map<String, dynamic>>{
      for (final r in usersRows) (r['id'] ?? '').toString(): r,
    };
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.45,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        builder: (ctx, scrollCtrl) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  'Переслать',
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scrollCtrl,
                  itemCount: peerIds.length,
                  itemBuilder: (c, i) {
                    final id = peerIds[i];
                    final u = byId[id];
                    final name = (u?['name'] as String?)?.trim();
                    final avatar = u?['avatar'] as String?;
                    return ListTile(
                      leading: CachedAvatar(
                        imageUrl: avatar,
                        radius: 22,
                        enableLightboxOnTap: false,
                      ),
                      title: Text(
                        (name == null || name.isEmpty) ? 'Пользователь' : name,
                      ),
                      onTap: () async {
                        Navigator.pop(ctx);
                        await _forwardMessageToPeer(message, id);
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<List<String>> _recentDmPeerIds({required Set<String> excluding}) async {
    final me = _me();
    if (me == null) return [];
    try {
      final rows = await _client
          .from(SupabaseConstants.messagesTable)
          .select('sender_id, receiver_id, created_at')
          .or('sender_id.eq.$me,receiver_id.eq.$me')
          .order('created_at', ascending: false)
          .limit(400);
      final out = <String>[];
      final seen = <String>{};
      for (final r in rows) {
        final s = (r['sender_id'] ?? '').toString();
        final rv = (r['receiver_id'] ?? '').toString();
        final peer = s == me ? rv : s;
        if (peer.isEmpty || excluding.contains(peer) || seen.contains(peer)) {
          continue;
        }
        seen.add(peer);
        out.add(peer);
        if (out.length >= 50) break;
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<void> _forwardMessageToPeer(
    Map<String, dynamic> source,
    String targetPeerId,
  ) async {
    final me = _me();
    if (me == null) return;
    final srcId = (source['id'] ?? '').toString();
    final msgType = (source['message_type'] as String?) ?? 'text';
    final text = source['text'] as String? ?? '';
    final audioUrl = source['audio_url'] as String?;
    final videoUrl = source['video_url'] as String?;
    final durationSec = (source['duration_seconds'] as int?) ?? 0;
    setState(() => _sending = true);
    try {
      final row = <String, dynamic>{
        'sender_id': me,
        'receiver_id': targetPeerId,
        'text': text,
        'message_type': msgType,
        'duration_seconds': durationSec,
      };
      if (audioUrl != null && audioUrl.isNotEmpty) {
        row['audio_url'] = audioUrl;
      }
      if (videoUrl != null && videoUrl.isNotEmpty) {
        row['video_url'] = videoUrl;
      }
      if (srcId.isNotEmpty) {
        row['forward_of'] = srcId;
      }
      await _client.from(SupabaseConstants.messagesTable).insert(row);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сообщение переслано')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось переслать: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showDirectMessageActions(Map<String, dynamic> m, String messageId) {
    final text = (m['text'] as String?) ?? '';
    final canCopy = text.trim().isNotEmpty &&
        !text.startsWith(_storyDmPrefix) &&
        !text.startsWith(_postDmPrefix);
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.mood_outlined),
              title: const Text('Реакция'),
              onTap: () {
                Navigator.pop(ctx);
                _showReactionPickerSheet(messageId);
              },
            ),
            ListTile(
              leading: const Icon(Icons.forward_rounded),
              title: const Text('Переслать'),
              onTap: () {
                Navigator.pop(ctx);
                unawaited(_openForwardPeerPicker(m));
              },
            ),
            ListTile(
              leading: const Icon(Icons.checklist_rtl_outlined),
              title: const Text('Выбрать'),
              onTap: () {
                Navigator.pop(ctx);
                _toggleSelectionMode(true);
                _toggleMessageSelection(messageId);
              },
            ),
            if (canCopy)
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: const Text('Копировать текст'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await Clipboard.setData(ClipboardData(text: text));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Скопировано')),
                    );
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _onQuickDoubleTapReaction(String messageId) async {
    await _setReactionForMessage(messageId, '❤️');
  }

  Stream<List<Map<String, dynamic>>> _messagesStream(String? me) {
    if (me == null) return const Stream.empty();
    final peer = widget.peerId;
    final hiddenIds = context.read<ChatListStorage>().getHiddenMessageIds(peer);

    // Два стрима с серверной фильтрацией по sender_id —
    // клиент получает только сообщения отправленные me или peer, а не всю таблицу.
    // Финальный фильтр по receiver_id выполняется на клиенте внутри merge.
    final sentStream = _client
        .from(SupabaseConstants.messagesTable)
        .stream(primaryKey: ['id'])
        .eq('sender_id', me);

    final receivedStream = _client
        .from(SupabaseConstants.messagesTable)
        .stream(primaryKey: ['id'])
        .eq('sender_id', peer);

    return _mergeDialogStreams(sentStream, receivedStream, me, peer, hiddenIds);
  }

  Stream<List<Map<String, dynamic>>> _mergeDialogStreams(
    Stream<List<Map<String, dynamic>>> stream1,
    Stream<List<Map<String, dynamic>>> stream2,
    String me,
    String peer,
    Set<String> hiddenIds,
  ) {
    List<Map<String, dynamic>> latest1 = const [];
    List<Map<String, dynamic>> latest2 = const [];
    var ready1 = false;
    var ready2 = false;
    var initialMergeDone = false;
    late final StreamController<List<Map<String, dynamic>>> controller;
    StreamSubscription<List<Map<String, dynamic>>>? sub1, sub2;

    void emit() {
      // Пока не пришёл хотя бы один снимок с каждой стороны — не шлём пустой список
      // (иначе сообщения «мигают» при подключении Realtime).
      if (!initialMergeDone) {
        if (!ready1 || !ready2) return;
        initialMergeDone = true;
      }

      final combined = <String, Map<String, dynamic>>{};
      for (final msg in latest1) {
        if ((msg['receiver_id'] ?? '') == peer) {
          final id = (msg['id'] ?? '').toString();
          if (id.isNotEmpty) combined[id] = msg;
        }
      }
      for (final msg in latest2) {
        if ((msg['receiver_id'] ?? '') == me) {
          final id = (msg['id'] ?? '').toString();
          if (id.isNotEmpty) combined[id] = msg;
        }
      }
      var result = combined.values.toList()
        ..sort(
          (a, b) => ((a['created_at'] ?? '') as Object).toString().compareTo(
                ((b['created_at'] ?? '') as Object).toString(),
              ),
        );
      if (hiddenIds.isNotEmpty) {
        result.removeWhere(
          (m) => hiddenIds.contains((m['id'] ?? '').toString()),
        );
      }
      const maxMessages = 200;
      if (result.length > maxMessages) {
        result = result.sublist(result.length - maxMessages);
      }
      controller.add(result);
    }

    controller = StreamController<List<Map<String, dynamic>>>(
      onListen: () {
        sub1 = stream1.listen(
          (data) {
            latest1 = data;
            ready1 = true;
            emit();
          },
          onError: controller.addError,
        );
        sub2 = stream2.listen(
          (data) {
            latest2 = data;
            ready2 = true;
            emit();
          },
          onError: controller.addError,
        );
      },
      onCancel: () {
        sub1?.cancel();
        sub2?.cancel();
      },
    );

    return controller.stream;
  }

  /// Оптимистичные строки, которых ещё нет в стриме (без мутации [_optimisticMessages] во время build).
  List<Map<String, dynamic>> _pendingOptimisticForStream(
    List<Map<String, dynamic>> streamMessages,
  ) {
    final now = DateTime.now();
    return _optimisticMessages.where((opt) {
      final createdRaw = opt['created_at'] as String?;
      final t = DateTime.tryParse(createdRaw ?? '');
      if (t != null && now.difference(t).inSeconds > 180) {
        return false;
      }
      return !_optimisticMatchesStreamRow(opt, streamMessages);
    }).toList();
  }

  bool _optimisticMatchesStreamRow(
    Map<String, dynamic> opt,
    List<Map<String, dynamic>> stream,
  ) {
    final oid = (opt['id'] ?? '').toString();
    if (oid.isNotEmpty && !oid.startsWith('tmp_')) {
      return stream.any((m) => (m['id']?.toString() ?? '') == oid);
    }
    final optSender = (opt['sender_id'] ?? '').toString();
    final optText = opt['text'] as String? ?? '';
    final optType = (opt['message_type'] as String?) ?? 'text';
    final optTime = DateTime.tryParse((opt['created_at'] as String?) ?? '');
    final optAudio = opt['audio_url'] as String?;
    final optVideo = opt['video_url'] as String?;
    final optImage = opt['image_url'] as String?;

    return stream.any((m) {
      if ((m['sender_id'] ?? '').toString() != optSender) return false;
      if (((m['message_type'] as String?) ?? 'text') != optType) return false;
      if ((m['text'] as String? ?? '') != optText) return false;
      if (optType == 'audio' &&
          optAudio != null &&
          (m['audio_url'] as String?) == optAudio) {
        return true;
      }
      if (optType == 'video_circle' &&
          optVideo != null &&
          (m['video_url'] as String?) == optVideo) {
        return true;
      }
      if (optType == 'image') {
        final mUrl = m['image_url'] as String?;
        if (optImage != null &&
            optImage.startsWith('http') &&
            mUrl == optImage) {
          return true;
        }
      }
      final mTime = DateTime.tryParse((m['created_at'] as String?) ?? '');
      if (mTime == null || optTime == null) return false;
      return mTime.difference(optTime).abs().inSeconds < 20;
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    final uid = _me();
    if (text.isEmpty || uid == null || _sending) return;

    // ── Оптимистичный UI: сообщение видно мгновенно ──────────
    final tempId = 'tmp_${DateTime.now().millisecondsSinceEpoch}';
    final optimistic = <String, dynamic>{
      'id': tempId,
      'sender_id': uid,
      'receiver_id': widget.peerId,
      'text': text,
      'created_at': DateTime.now().toIso8601String(),
      'message_type': 'text',
      '_pending': true,
    };
    setState(() {
      _optimisticMessages.add(optimistic);
      _sending = true;
    });
    // Очищаем поле и скроллим сразу — не ждём сервер
    _controller.clear();
    _textHasContent.value = false;
    _forceScrollToLatest = true;
    // ─────────────────────────────────────────────────────────

    try {
      final inserted = await _client
          .from(SupabaseConstants.messagesTable)
          .insert({
            'sender_id': uid,
            'receiver_id': widget.peerId,
            'text': text,
          })
          .select()
          .maybeSingle();
      // Подменяем tmp на строку с сервера — нет «дыры» до события Realtime.
      if (mounted && inserted != null) {
        setState(() {
          final idx = _optimisticMessages.indexWhere((m) => m['id'] == tempId);
          if (idx >= 0) {
            _optimisticMessages[idx] =
                Map<String, dynamic>.from(inserted as Map);
          }
        });
      }
    } catch (e) {
      // Откат: убираем оптимистичное сообщение при ошибке
      if (!mounted) return;
      setState(() {
        _optimisticMessages.removeWhere((m) => m['id'] == tempId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Не удалось отправить: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom({bool animated = false}) {
    if (!_messagesScrollController.hasClients) return;
    final bottom = _messagesScrollController.position.minScrollExtent;
    if (animated) {
      _messagesScrollController.animateTo(
        bottom,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } else {
      _messagesScrollController.jumpTo(bottom);
    }
  }

  void _handleScroll() {
    if (!_messagesScrollController.hasClients) return;
    final position = _messagesScrollController.position;
    final distanceFromBottom = position.pixels - position.minScrollExtent;
    final shouldShow = distanceFromBottom > 160;
    final isNearBottom = distanceFromBottom < 120;
    if (shouldShow != _showScrollToBottom ||
        (isNearBottom && _showNewMessagesHint)) {
      setState(() {
        _showScrollToBottom = shouldShow;
        if (isNearBottom) {
          _showNewMessagesHint = false;
        }
      });
    }
    if (isNearBottom) {
      _scheduleMarkReadIfVisible();
    }
  }

  void _openPeerProfile() {
    context.push('/profile/${widget.peerId}');
  }

  void _toggleSelectionMode([bool? enabled]) {
    setState(() {
      _selectionMode = enabled ?? !_selectionMode;
      if (!_selectionMode) {
        _selectedMessageIds.clear();
      }
    });
  }

  void _toggleMessageSelection(String messageId) {
    if (messageId.isEmpty) return;
    setState(() {
      if (_selectedMessageIds.contains(messageId)) {
        _selectedMessageIds.remove(messageId);
      } else {
        _selectedMessageIds.add(messageId);
      }
    });
  }

  Future<void> _deleteSelectedMessages() async {
    final uid = _me();
    if (_selectedMessageIds.isEmpty || uid == null) return;
    final selected = _selectedMessageIds.toList(growable: false);
    final chatStorage = context.read<ChatListStorage>();
    final unreadController = context.read<ChatUnreadBadgeController>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _client
          .from(SupabaseConstants.messagesTable)
          .delete()
          .inFilter('id', selected)
          .or(
            'and(sender_id.eq.$uid,receiver_id.eq.${widget.peerId}),'
            'and(sender_id.eq.${widget.peerId},receiver_id.eq.$uid)',
          );
      if (!mounted) return;
      await chatStorage.clearPeerState('direct:${widget.peerId}');
      setState(() {
        _selectedMessageIds.clear();
        _selectionMode = false;
      });
      unreadController.refresh();
      messenger.showSnackBar(
        const SnackBar(content: Text('Сообщения удалены навсегда')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось удалить сообщения: $e')),
      );
    }
  }

  Future<void> _deleteAllMessagesInDialog() async {
    final uid = _me();
    if (uid == null) return;
    final chatStorage = context.read<ChatListStorage>();
    final unreadController = context.read<ChatUnreadBadgeController>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _client.rpc('delete_chat', params: {'peer_id': widget.peerId});
    } catch (_) {
      await _client
          .from(SupabaseConstants.messagesTable)
          .delete()
          .eq('sender_id', uid)
          .eq('receiver_id', widget.peerId);
      await _client
          .from(SupabaseConstants.messagesTable)
          .delete()
          .eq('sender_id', widget.peerId)
          .eq('receiver_id', uid);
    }
    if (!mounted) return;
    await chatStorage.clearPeerState('direct:${widget.peerId}');
    setState(() {
      _selectedMessageIds.clear();
      _selectionMode = false;
      _didInitialAutoScroll = false;
      _showNewMessagesHint = false;
      _showScrollToBottom = false;
      _lastMessageCount = 0;
      _lastLatestMessageId = null;
    });
    unreadController.refresh();
    messenger.showSnackBar(
      const SnackBar(content: Text('Вся переписка удалена навсегда')),
    );
  }

  Future<void> _confirmDeleteSelected() async {
    if (_selectedMessageIds.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Удалить выбранные сообщения?'),
        content: Text(
          'Будет удалено: ${_selectedMessageIds.length}. Это действие нельзя отменить.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _deleteSelectedMessages();
    }
  }

  List<Map<String, dynamic>> _selectedMessages() {
    if (_selectedMessageIds.isEmpty || _latestDialogMessages.isEmpty) {
      return const [];
    }
    return _latestDialogMessages
        .where((m) => _selectedMessageIds.contains((m['id'] ?? '').toString()))
        .toList();
  }

  bool _canEditSelectedMessage() {
    final uid = _me();
    if (uid == null) return false;
    final selected = _selectedMessages();
    if (selected.length != 1) return false;
    final m = selected.first;
    final senderId = (m['sender_id'] ?? '').toString();
    final text = (m['text'] ?? '').toString().trim();
    if (senderId != uid) return false;
    if (text.isEmpty) return false;
    if (text.startsWith(_postDmPrefix) || text.startsWith(_storyDmPrefix)) {
      return false;
    }
    return true;
  }

  Future<void> _editSelectedMessage() async {
    final selected = _selectedMessages();
    final uid = _me();
    if (selected.length != 1 || uid == null) return;
    final message = selected.first;
    final messageId = (message['id'] ?? '').toString();
    final oldText = (message['text'] ?? '').toString();
    final controller = TextEditingController(text: oldText);
    final String? nextText;
    try {
      nextText = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Изменить сообщение'),
          content: TextField(
            controller: controller,
            minLines: 1,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText: 'Введите новый текст',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, controller.text.trim()),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
    if (nextText == null || nextText.isEmpty || nextText == oldText.trim()) {
      return;
    }
    try {
      await _client
          .from(SupabaseConstants.messagesTable)
          .update({'text': nextText})
          .eq('id', messageId)
          .eq('sender_id', uid)
          .eq('receiver_id', widget.peerId);
      if (!mounted) return;
      setState(() {
        _selectionMode = false;
        _selectedMessageIds.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сообщение изменено')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось изменить сообщение: $e')),
      );
    }
  }

  Future<void> _deleteSelectedForMe() async {
    if (_selectedMessageIds.isEmpty) return;
    final chatStorage = context.read<ChatListStorage>();
    final unreadController = context.read<ChatUnreadBadgeController>();
    final selected = _selectedMessageIds.toList(growable: false);
    await chatStorage.addHiddenMessageIds(widget.peerId, selected);
    if (!mounted) return;
    setState(() {
      _selectionMode = false;
      _selectedMessageIds.clear();
    });
    unreadController.refresh();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Сообщения удалены у вас')),
    );
  }

  Future<void> _showDeleteSelectedOptions() async {
    if (_selectedMessageIds.isEmpty) return;
    final selectedCount = _selectedMessageIds.length;
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text('Удалить у меня ($selectedCount)'),
              onTap: () async {
                Navigator.pop(ctx);
                await _deleteSelectedForMe();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: Text(
                'Удалить у всех ($selectedCount)',
                style: const TextStyle(color: Colors.red),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                await _confirmDeleteSelected();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Удалить весь чат?'),
        content: const Text(
          'Вся переписка будет удалена навсегда и не сохранится в кэше.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Удалить всё'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _deleteAllMessagesInDialog();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      return Scaffold(
        appBar: AppBar(
          title: GestureDetector(
            onTap: _openPeerProfile,
            behavior: HitTestBehavior.opaque,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: Text(widget.peerName)),
                const SizedBox(width: 6),
                const Icon(Icons.open_in_new, size: 18),
              ],
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Войдите, чтобы писать сообщения'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.push('/login'),
                child: const Text('Войти'),
              ),
            ],
          ),
        ),
      );
    }

    final sessionUid = authState.user.id;
    final themeNotifier = context.read<ThemeIndexNotifier>();

    return ListenableBuilder(
      listenable: themeNotifier.listenable,
      builder: (context, _) {
        final decoration = themeDecoration(
          themeNotifier.value,
          themeNotifier.customImagePath,
        );
        return Container(
          decoration: decoration,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              title: _selectionMode
                  ? Text('Выбрано: ${_selectedMessageIds.length}')
                  : GestureDetector(
                      onTap: _openPeerProfile,
                      behavior: HitTestBehavior.opaque,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  widget.peerName,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(Icons.open_in_new, size: 18),
                            ],
                          ),
                          StreamBuilder<List<Map<String, dynamic>>>(
                            stream: _peerPresenceStream(),
                            builder: (context, snap) {
                              DateTime? last;
                              final rows = snap.data;
                              if (rows != null && rows.isNotEmpty) {
                                last = _parseTs(rows.first['last_active_at']);
                              }
                              final online = _isPeerOnline(last);
                              final subStyle =
                                  Theme.of(context).textTheme.labelSmall;
                              return Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (online) ...[
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFF34B233),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                    ],
                                    Flexible(
                                      child: Text(
                                        _formatPeerPresenceSubtitle(last),
                                        style: subStyle?.copyWith(
                                          color: online
                                              ? const Color(0xFF34B233)
                                              : Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
              leading: IconButton(
                icon: Icon(_selectionMode ? Icons.close : Icons.arrow_back),
                onPressed: () {
                  if (_selectionMode) {
                    _toggleSelectionMode(false);
                    return;
                  }
                  context.pop();
                },
              ),
              actions: [
                if (_selectionMode) ...[
                  IconButton(
                    tooltip: 'Удалить выбранные',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _selectedMessageIds.isEmpty
                        ? null
                        : _showDeleteSelectedOptions,
                  ),
                  IconButton(
                    tooltip: 'Изменить',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed:
                        _canEditSelectedMessage() ? _editSelectedMessage : null,
                  ),
                  IconButton(
                    tooltip: 'Удалить все',
                    icon: const Icon(Icons.delete_sweep_outlined),
                    onPressed: _confirmDeleteAll,
                  ),
                ] else ...[
                  IconButton(
                    icon: const Icon(Icons.palette_outlined),
                    onPressed: _showThemePicker,
                  ),
                ],
              ],
            ),
            body: Stack(
              children: [
                Column(
                  children: [
                    Expanded(
                      child: StreamBuilder<List<Map<String, dynamic>>>(
                        key: ValueKey<String>('dm_${sessionUid}_${widget.peerId}'),
                        stream: _messagesStream(sessionUid),
                        builder: (context, snapshot) {
                      final streamMessages = snapshot.data ?? const [];

                      final pending =
                          _pendingOptimisticForStream(streamMessages);

                      final messages = [
                        ...streamMessages,
                        ...pending,
                      ]..sort((a, b) =>
                          ((a['created_at'] as String?) ?? '').compareTo(
                              (b['created_at'] as String?) ?? ''));

                      if (snapshot.connectionState ==
                              ConnectionState.waiting &&
                          streamMessages.isEmpty &&
                          pending.isEmpty) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            'Ошибка загрузки сообщений',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        );
                      }
                      if (messages.isEmpty) {
                        return Center(
                          child: Text(
                            'Напишите первое сообщение',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        );
                      }
                      final me = sessionUid;
                      _latestDialogMessages = messages;
                      _scheduleReactionsFetch(messages);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        final before = _optimisticMessages.length;
                        _optimisticMessages.removeWhere(
                          (o) => _optimisticMatchesStreamRow(o, streamMessages),
                        );
                        if (before != _optimisticMessages.length) {
                          setState(() {});
                        }
                        if (!_messagesScrollController.hasClients) return;
                        final position = _messagesScrollController.position;
                        final isNearBottom =
                            (position.pixels - position.minScrollExtent) < 120;
                        final latestMessageId = messages.isNotEmpty
                            ? (messages.last['id']?.toString() ?? '')
                            : '';
                        final hasNewLatestMessage = latestMessageId.isNotEmpty &&
                            latestMessageId != _lastLatestMessageId;
                        if (!_didInitialAutoScroll) {
                          _didInitialAutoScroll = true;
                          _lastMessageCount = messages.length;
                          _lastLatestMessageId = latestMessageId;
                          _scrollToBottom();
                          _scheduleMarkReadIfVisible();
                          return;
                        }
                        final hasNewMessages = messages.length > _lastMessageCount;
                        _lastMessageCount = messages.length;
                        _lastLatestMessageId = latestMessageId;
                        if (_forceScrollToLatest) {
                          _forceScrollToLatest = false;
                          if (_showNewMessagesHint) {
                            setState(() => _showNewMessagesHint = false);
                          }
                          _scrollToBottom();
                          _scheduleMarkReadIfVisible();
                        } else if (isNearBottom && hasNewLatestMessage) {
                          // Keep user pinned only when they already stay at latest.
                          _scrollToBottom();
                          _scheduleMarkReadIfVisible();
                        } else if ((hasNewMessages || hasNewLatestMessage) &&
                            !_showNewMessagesHint &&
                            !isNearBottom) {
                          setState(() => _showNewMessagesHint = true);
                        }
                      });
                      return NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          _handleScroll();
                          return false;
                        },
                        child: ListView.builder(
                          controller: _messagesScrollController,
                          reverse: true,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                          final m = messages[messages.length - 1 - index];
                          final messageId = (m['id'] ?? '').toString();
                          final senderId = m['sender_id'] as String?;
                          final text = m['text'] as String? ?? '';
                          final msgType = (m['message_type'] as String?) ?? 'text';
                          final audioUrl = m['audio_url'] as String?;
                          final videoUrl = m['video_url'] as String?;
                          final imageUrl = m['image_url'] as String?;
                          final isLocalImage = m['_local'] == true;
                          final durationSec = (m['duration_seconds'] as int?) ?? 0;
                          final structured = _parseStoryDirectMessage(text);
                          final postStructured = _parsePostDirectMessage(text);
                          final locationData = _parseLocationMessage(text);
                          final isMe = senderId == me;
                          final isSelected =
                              messageId.isNotEmpty &&
                              _selectedMessageIds.contains(messageId);
                          final forwardOf = m['forward_of'];
                          final reactionRows =
                              _reactionsByMessageId[messageId] ?? const [];
                          final bubbleBackground = isSelected
                              ? Theme.of(context)
                                  .colorScheme
                                  .secondaryContainer
                              : msgType == 'audio'
                                  ? (isMe
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.grey.shade200)
                                  : isMe
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.grey.shade200;
                          final useVideoShell = msgType == 'video_circle' &&
                              forwardOf == null &&
                              !isSelected;
                          return Align(
                            alignment: isMe
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: GestureDetector(
                              onDoubleTap: _selectionMode
                                  ? null
                                  : () =>
                                      unawaited(_onQuickDoubleTapReaction(messageId)),
                              onLongPress: () {
                                if (_selectionMode) {
                                  _toggleMessageSelection(messageId);
                                } else {
                                  _showDirectMessageActions(m, messageId);
                                }
                              },
                              onTap: _selectionMode
                                  ? () => _toggleMessageSelection(messageId)
                                  : null,
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                padding: useVideoShell
                                    ? EdgeInsets.zero
                                    : EdgeInsets.symmetric(
                                        horizontal:
                                            msgType == 'video_circle' ? 10 : 12,
                                        vertical:
                                            msgType == 'video_circle' ? 8 : 8,
                                      ),
                                decoration: useVideoShell
                                    ? null
                                    : BoxDecoration(
                                        color: bubbleBackground,
                                        borderRadius: BorderRadius.circular(16),
                                        border: isSelected
                                            ? Border.all(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary,
                                                width: 1.2,
                                              )
                                            : null,
                                      ),
                                child: Column(
                                  crossAxisAlignment: isMe
                                      ? CrossAxisAlignment.end
                                      : CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (forwardOf != null)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 6),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.forward_rounded,
                                              size: 14,
                                              color: isMe
                                                  ? Colors.white70
                                                  : Colors.black54,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Переслано',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontStyle: FontStyle.italic,
                                                color: isMe
                                                    ? Colors.white70
                                                    : Colors.black54,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Flexible(
                                          child: msgType == 'image' &&
                                                  imageUrl != null
                                              ? _ImageMessageBubble(
                                                  key: ValueKey('img_$messageId'),
                                                  imageUrl: imageUrl,
                                                  isLocal: isLocalImage,
                                                  isMe: isMe,
                                                  isPending: m['_pending'] == true,
                                                )
                                              : locationData != null
                                                  ? _LocationBubble(
                                                      key: ValueKey('loc_$messageId'),
                                                      lat: locationData.$1,
                                                      lng: locationData.$2,
                                                      isMe: isMe,
                                                    )
                                                  : msgType == 'audio' &&
                                                          audioUrl != null
                                                      ? _VoiceMessageBubble(
                                                          key: ValueKey('audio_$messageId'),
                                                          audioUrl: audioUrl,
                                                          durationSeconds: durationSec,
                                                          isMe: isMe,
                                                        )
                                                      : msgType == 'video_circle' &&
                                                              videoUrl != null
                                                          ? _RoundVideoBubble(
                                                              key: ValueKey(
                                                                  'video_$messageId'),
                                                              videoUrl: videoUrl,
                                                              isMe: isMe,
                                                            )
                                                          : postStructured != null
                                                      ? _PostLinkedChatBubble(
                                                          message: postStructured,
                                                          isMe: isMe,
                                                          onOpenPost: _selectionMode
                                                              ? () =>
                                                                  _toggleMessageSelection(
                                                                      messageId)
                                                              : () {
                                                                  context.push(
                                                                    '/post/${postStructured.postId}',
                                                                  );
                                                                },
                                                          onShare: () async {
                                                            if (_selectionMode) {
                                                              return;
                                                            }
                                                            await SharePlus
                                                                .instance
                                                                .share(
                                                              ShareParams(
                                                                text:
                                                                    'https://tmr-tau.app/post/${postStructured.postId}',
                                                              ),
                                                            );
                                                          },
                                                          onSave: () async {
                                                            if (_selectionMode) {
                                                              return;
                                                            }
                                                            if (sessionUid
                                                                .isEmpty) {
                                                              return;
                                                            }
                                                            final postRepo =
                                                                context.read<
                                                                    PostRepository>();
                                                            final messenger =
                                                                ScaffoldMessenger
                                                                    .of(context);
                                                            try {
                                                              await postRepo
                                                                  .toggleSave(
                                                                postStructured
                                                                    .postId,
                                                                sessionUid,
                                                              );
                                                              if (!mounted) {
                                                                return;
                                                              }
                                                              messenger
                                                                  .showSnackBar(
                                                                const SnackBar(
                                                                  content: Text(
                                                                      'Публикация сохранена'),
                                                                ),
                                                              );
                                                            } catch (_) {
                                                              if (!mounted) {
                                                                return;
                                                              }
                                                              messenger
                                                                  .showSnackBar(
                                                                const SnackBar(
                                                                  content: Text(
                                                                      'Не удалось сохранить публикацию'),
                                                                ),
                                                              );
                                                            }
                                                          },
                                                        )
                                                      : structured == null
                                                          ? Text(
                                                              text,
                                                              style: TextStyle(
                                                                color: isMe
                                                                    ? Colors.white
                                                                    : Colors
                                                                        .black87,
                                                              ),
                                                            )
                                                          : _StoryLinkedChatBubble(
                                                              message:
                                                                  structured,
                                                              isMe: isMe,
                                                              onOpenStory:
                                                                  _selectionMode
                                                                      ? () =>
                                                                          _toggleMessageSelection(
                                                                              messageId)
                                                                      : () =>
                                                                          _openStoryFromMessage(
                                                                            structured
                                                                                .storyId,
                                                                          ),
                                                            ),
                                        ),
                                        if (isMe) ...[
                                          const SizedBox(width: 4),
                                          Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 2),
                                            // Pending: часики; подтверждено: галочки
                                            child: m['_pending'] == true
                                                ? Icon(
                                                    Icons.access_time_rounded,
                                                    size: 13,
                                                    color: Colors.white
                                                        .withValues(alpha: 0.7),
                                                  )
                                                : _ReadReceiptTicks(
                                                    readAt: m['read_at'],
                                                    outgoingOnPrimary: true,
                                                  ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    if (reactionRows.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: _DmReactionStrip(
                                          rows: reactionRows,
                                          currentUserId: me,
                                          alignEnd: isMe,
                                          onReactionTap: (emoji) => unawaited(
                                            _setReactionForMessage(
                                                messageId, emoji),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                          },
                        ),
                      );
                    },
                  ),
                ),
                if (!_selectionMode)
                  SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ── Панель эмодзи (анимированная) ──
                        AnimatedSize(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                          child: _showEmojiPanel
                              ? _EmojiPanel(
                                  onEmojiSelected: (emoji) {
                                    final ctrl = _controller;
                                    final sel = ctrl.selection;
                                    final pos = sel.isValid
                                        ? sel.start
                                        : ctrl.text.length;
                                    final t = ctrl.text;
                                    final newText =
                                        t.substring(0, pos) +
                                        emoji +
                                        t.substring(pos);
                                    ctrl.value = TextEditingValue(
                                      text: newText,
                                      selection:
                                          TextSelection.collapsed(
                                              offset:
                                                  pos + emoji.length),
                                    );
                                    _textHasContent.value =
                                        newText.trim().isNotEmpty;
                                  },
                                  onGifSelected: (url) {
                                    // GIF как изображение
                                    setState(() => _showEmojiPanel = false);
                                    _sendImageUrl(url);
                                  },
                                )
                              : const SizedBox.shrink(),
                        ),
                        // ── Input bar (WhatsApp-стиль) ──
                        Material(
                          color: ThemedContentSurface.scaffoldElevated,
                          elevation: _showEmojiPanel ? 0 : 6,
                          shadowColor: Colors.black26,
                          child: Padding(
                            padding:
                                const EdgeInsets.fromLTRB(4, 6, 4, 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                // ➕ Вложения
                                _ChatIconBtn(
                                  icon: Icons.add_circle_outline_rounded,
                                  onTap: _showAttachmentSheet,
                                ),
                                // 😊 Эмодзи
                                _ChatIconBtn(
                                  icon: _showEmojiPanel
                                      ? Icons.keyboard_rounded
                                      : Icons.emoji_emotions_outlined,
                                  onTap: () {
                                    FocusScope.of(context).unfocus();
                                    setState(() => _showEmojiPanel =
                                        !_showEmojiPanel);
                                  },
                                ),
                                const SizedBox(width: 2),
                                // Поле ввода
                                Expanded(
                                  child: Container(
                                    constraints: const BoxConstraints(
                                        maxHeight: 120),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius:
                                          BorderRadius.circular(24),
                                    ),
                                    child: TextField(
                                      controller: _controller,
                                      minLines: 1,
                                      maxLines: 5,
                                      textInputAction:
                                          TextInputAction.newline,
                                      onChanged: (v) {
                                        _textHasContent.value =
                                            v.trim().isNotEmpty;
                                        if (_showEmojiPanel &&
                                            v.isNotEmpty) {
                                          setState(() =>
                                              _showEmojiPanel = false);
                                        }
                                      },
                                      onTap: () {
                                        if (_showEmojiPanel) {
                                          setState(() =>
                                              _showEmojiPanel = false);
                                        }
                                      },
                                      decoration: InputDecoration(
                                        hintText: 'Сообщение',
                                        hintStyle: TextStyle(
                                            color: Colors.grey.shade500,
                                            fontSize: 15),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 16,
                                                vertical: 11),
                                        border: InputBorder.none,
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                // Кнопки справа
                                ValueListenableBuilder<bool>(
                                  valueListenable: _textHasContent,
                                  builder: (context2, hasContent, child2) {
                                    if (hasContent) {
                                      return _SendBtn(
                                          onTap: _sendMessage);
                                    }
                                    return Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // 📷 Круглое видео
                                        _ChatIconBtn(
                                          icon:
                                              Icons.camera_alt_rounded,
                                          onTap:
                                              _pickAndSendRoundVideo,
                                        ),
                                        // 🎤 Голосовое (удержать)
                                        _VoiceMicButton(
                                          isRecording:
                                              _isRecordingVoice,
                                          seconds: _voiceRecordSeconds,
                                          onHoldStart:
                                              _startVoiceRecording,
                                          onHoldEnd: _stopVoiceRecording,
                                          onHoldCancel:
                                              _cancelVoiceRecording,
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ],
                ),
                Positioned(
                  right: 16,
                  bottom: 92,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: (_showScrollToBottom || _showNewMessagesHint)
                        ? Material(
                            key: ValueKey(_showNewMessagesHint),
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(999),
                              onTap: () {
                                _scrollToBottom(animated: true);
                                if (_showNewMessagesHint) {
                                  setState(() => _showNewMessagesHint = false);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  borderRadius: BorderRadius.circular(999),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 8,
                                      offset: Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      color:
                                          Theme.of(context).colorScheme.onPrimary,
                                      size: 18,
                                    ),
                                    if (_showNewMessagesHint) ...[
                                      const SizedBox(width: 4),
                                      Text(
                                        'Новые',
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onPrimary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Голосовые сообщения ────────────────────────────────────

  Future<void> _startVoiceRecording() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted || !mounted) return;
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    try {
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );
    } on MissingPluginException {
      _showVoicePluginMissing();
      return;
    } catch (_) {
      return;
    }
    _voiceRecordSeconds = 0;
    _voiceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _voiceRecordSeconds++);
    });
    if (mounted) setState(() => _isRecordingVoice = true);
  }

  Future<void> _stopVoiceRecording() async {
    if (!_isRecordingVoice) return;
    _voiceTimer?.cancel();
    String? path;
    try {
      path = await _audioRecorder.stop();
    } on MissingPluginException {
      _showVoicePluginMissing();
      return;
    }
    final secs = _voiceRecordSeconds;
    if (mounted) setState(() => _isRecordingVoice = false);
    if (path == null || secs < 1 || !mounted) return;
    await _uploadAndSendVoice(File(path), secs);
  }

  Future<void> _cancelVoiceRecording() async {
    if (!_isRecordingVoice) return;
    _voiceTimer?.cancel();
    try {
      await _audioRecorder.stop();
    } on MissingPluginException {
      _showVoicePluginMissing();
      return;
    }
    if (mounted) setState(() => _isRecordingVoice = false);
  }

  void _showVoicePluginMissing() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Голосовые временно недоступны на этой сборке приложения'),
      ),
    );
  }

  Future<void> _uploadAndSendVoice(File file, int durationSeconds) async {
    final uid = _me();
    if (uid == null || !mounted) return;
    setState(() => _sending = true);
    try {
      final bytes = await file.readAsBytes();
      final uploadPath = '$uid/${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _client.storage.from('chat_media').uploadBinary(
        uploadPath,
        bytes,
        fileOptions:
            const FileOptions(contentType: 'audio/m4a', upsert: false),
      );
      final url =
          _client.storage.from('chat_media').getPublicUrl(uploadPath);
      await _client.from(SupabaseConstants.messagesTable).insert({
        'sender_id': uid,
        'receiver_id': widget.peerId,
        'text': '',
        'message_type': 'audio',
        'audio_url': url,
        'duration_seconds': durationSeconds,
      });
      _forceScrollToLatest = true;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось отправить голосовое: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ── Круглые видео ──────────────────────────────────────────

  Future<void> _pickAndSendRoundVideo() async {
    final camStatus = await Permission.camera.request();
    final micStatus = await Permission.microphone.request();
    if (!camStatus.isGranted || !micStatus.isGranted || !mounted) return;

    final picker = ImagePicker();
    final xFile = await picker.pickVideo(
      source: ImageSource.camera,
      maxDuration: const Duration(seconds: 60),
    );
    if (xFile == null || !mounted) return;

    final file = File(xFile.path);
    int durationSec = 0;
    try {
      final ctrl = VideoPlayerController.file(file);
      await ctrl.initialize();
      durationSec = ctrl.value.duration.inSeconds;
      await ctrl.dispose();
    } catch (_) {}

    setState(() => _sending = true);
    try {
      final bytes = await file.readAsBytes();
      final uploadPath =
          '${_me()}/${DateTime.now().millisecondsSinceEpoch}.mp4';
      await _client.storage.from('chat_media').uploadBinary(
        uploadPath,
        bytes,
        fileOptions:
            const FileOptions(contentType: 'video/mp4', upsert: false),
      );
      final url =
          _client.storage.from('chat_media').getPublicUrl(uploadPath);
      await _client.from(SupabaseConstants.messagesTable).insert({
        'sender_id': _me(),
        'receiver_id': widget.peerId,
        'text': '',
        'message_type': 'video_circle',
        'video_url': url,
        'duration_seconds': durationSec,
      });
      _forceScrollToLatest = true;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось отправить видео: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showThemePicker() {
    final themeNotifier = context.read<ThemeIndexNotifier>();
    showThemePickerSheet(
      context,
      currentIndex: themeNotifier.value,
      onSelect: (index) => themeNotifier.setIndex(index),
      onAddCustom: () async {
        final picker = ImagePicker();
        final xFile = await picker.pickImage(source: ImageSource.gallery);
        if (xFile == null || !mounted) return;
        final bytes = await xFile.readAsBytes();
        if (!mounted) return;
        await themeNotifier.setCustomThemeFromImageBytes(bytes);
      },
    );
  }

  // ── WhatsApp attachment sheet ──────────────────────────────

  void _showAttachmentSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _AttachmentSheet(
        onPhoto: () {
          Navigator.pop(sheetCtx);
          _pickAndSendPhoto(ImageSource.gallery);
        },
        onCamera: () {
          Navigator.pop(sheetCtx);
          _pickAndSendPhoto(ImageSource.camera);
        },
        onLocation: () {
          Navigator.pop(sheetCtx);
          _sendCurrentLocation();
        },
        onContact: () {
          Navigator.pop(sheetCtx);
          _showContactInput();
        },
        onDocument: () {
          Navigator.pop(sheetCtx);
          _showComingSoon('Документы');
        },
        onPoll: () {
          Navigator.pop(sheetCtx);
          _showComingSoon('Опросы');
        },
        onEvent: () {
          Navigator.pop(sheetCtx);
          _showComingSoon('Мероприятия');
        },
      ),
    );
  }

  void _showComingSoon(String label) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$label — скоро'),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _pickAndSendPhoto(ImageSource source) async {
    if (source == ImageSource.camera) {
      final s = await Permission.camera.request();
      if (!s.isGranted || !mounted) return;
    }
    final picker = ImagePicker();
    final xFile = await picker.pickImage(
      source: source,
      imageQuality: 82,
      maxWidth: 1440,
    );
    if (xFile == null || !mounted) return;
    final uid = _me();
    if (uid == null) return;

    // Показываем оптимистично с локальным путём
    final tempId = 'tmp_img_${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      _optimisticMessages.add({
        'id': tempId,
        'sender_id': uid,
        'receiver_id': widget.peerId,
        'text': '',
        'created_at': DateTime.now().toIso8601String(),
        'message_type': 'image',
        'image_url': xFile.path,
        '_pending': true,
        '_local': true,
      });
      _forceScrollToLatest = true;
    });

    try {
      final bytes = await xFile.readAsBytes();
      final ext = xFile.name.split('.').last.toLowerCase();
      final uploadPath =
          '$uid/img_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await _client.storage.from('chat_media').uploadBinary(
        uploadPath,
        bytes,
        fileOptions:
            FileOptions(contentType: 'image/$ext', upsert: false),
      );
      final url =
          _client.storage.from('chat_media').getPublicUrl(uploadPath);
      final inserted = await _client
          .from(SupabaseConstants.messagesTable)
          .insert({
            'sender_id': uid,
            'receiver_id': widget.peerId,
            'text': '',
            'message_type': 'image',
            'image_url': url,
          })
          .select()
          .maybeSingle();
      _forceScrollToLatest = true;
      if (mounted && inserted != null) {
        setState(() {
          final idx = _optimisticMessages.indexWhere((m) => m['id'] == tempId);
          if (idx >= 0) {
            _optimisticMessages[idx] =
                Map<String, dynamic>.from(inserted as Map);
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() =>
          _optimisticMessages.removeWhere((m) => m['id'] == tempId));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Не удалось отправить фото: $e'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _sendImageUrl(String url) async {
    final uid = _me();
    if (uid == null) return;
    try {
      await _client.from(SupabaseConstants.messagesTable).insert({
        'sender_id': uid,
        'receiver_id': widget.peerId,
        'text': '',
        'message_type': 'image',
        'image_url': url,
      });
      _forceScrollToLatest = true;
    } catch (_) {}
  }

  Future<void> _sendCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled || !mounted) {
      _showComingSoon('Местоположение недоступно');
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || !mounted) return;
    }
    if (permission == LocationPermission.deniedForever || !mounted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Разрешите доступ к геолокации в настройках'),
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }
    final uid = _me();
    if (uid == null) return;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 12),
        ),
      );
      final text =
          '__location__|${pos.latitude}|${pos.longitude}';
      final tempId =
          'tmp_loc_${DateTime.now().millisecondsSinceEpoch}';
      setState(() {
        _optimisticMessages.add({
          'id': tempId,
          'sender_id': uid,
          'receiver_id': widget.peerId,
          'text': text,
          'created_at': DateTime.now().toIso8601String(),
          'message_type': 'text',
          '_pending': true,
        });
        _forceScrollToLatest = true;
      });
      final inserted = await _client
          .from(SupabaseConstants.messagesTable)
          .insert({
            'sender_id': uid,
            'receiver_id': widget.peerId,
            'text': text,
          })
          .select()
          .maybeSingle();
      if (mounted && inserted != null) {
        setState(() {
          final idx = _optimisticMessages.indexWhere((m) => m['id'] == tempId);
          if (idx >= 0) {
            _optimisticMessages[idx] =
                Map<String, dynamic>.from(inserted as Map);
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Ошибка геолокации: $e'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  void _showContactInput() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dlg) => AlertDialog(
        title: const Text('Отправить контакт'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Имя'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: phoneCtrl,
              decoration: const InputDecoration(labelText: 'Телефон'),
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dlg),
              child: const Text('Отмена')),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final phone = phoneCtrl.text.trim();
              Navigator.pop(dlg);
              if (name.isEmpty && phone.isEmpty) return;
              final uid = _me();
              if (uid == null) return;
              final text =
                  '📋 Контакт\n👤 $name\n📞 $phone';
              await _client
                  .from(SupabaseConstants.messagesTable)
                  .insert({
                'sender_id': uid,
                'receiver_id': widget.peerId,
                'text': text,
              });
              _forceScrollToLatest = true;
            },
            child: const Text('Отправить'),
          ),
        ],
      ),
    );
  }

  (double, double)? _parseLocationMessage(String text) {
    if (!text.startsWith('__location__|')) return null;
    final parts = text.split('|');
    if (parts.length < 3) return null;
    final lat = double.tryParse(parts[1]);
    final lng = double.tryParse(parts[2]);
    if (lat == null || lng == null) return null;
    return (lat, lng);
  }

  // ─────────────────────────────────────────────────────────────

  _StoryDirectMessage? _parseStoryDirectMessage(String text) {
    if (!text.startsWith('$_storyDmPrefix|')) return null;
    final parts = text.split('|');
    if (parts.length < 5) return null;
    String decode(String value) {
      try {
        return Uri.decodeComponent(value);
      } catch (_) {
        return value;
      }
    }

    final kind = parts[1];
    final storyId = decode(parts[2]);
    final previewUrl = decode(parts[3]);
    final payload = decode(parts[4]);
    if (storyId.isEmpty) return null;
    return _StoryDirectMessage(
      kind: kind,
      storyId: storyId,
      previewUrl: previewUrl,
      payload: payload,
    );
  }

  _PostDirectMessage? _parsePostDirectMessage(String text) {
    if (!text.startsWith('$_postDmPrefix|')) return null;
    final parts = text.split('|');
    if (parts.length < 6) return null;
    String decode(String value) {
      try {
        return Uri.decodeComponent(value);
      } catch (_) {
        return value;
      }
    }
    final postId = decode(parts[1]);
    if (postId.isEmpty) return null;
    int parseCount(int index) {
      if (parts.length <= index) return 0;
      return int.tryParse(parts[index]) ?? 0;
    }
    return _PostDirectMessage(
      postId: postId,
      imageUrl: decode(parts[2]),
      caption: decode(parts[3]),
      authorName: decode(parts[4]),
      videoUrl: decode(parts[5]),
      likesCount: parseCount(6),
      commentsCount: parseCount(7),
      repostsCount: parseCount(8),
    );
  }

  Future<void> _openStoryFromMessage(String storyId) async {
    if (storyId.isEmpty) return;
    try {
      final groups = await context.read<StoriesRepository>().getStoriesGroupedByUser();
      if (!mounted) return;
      StoryGroupEntity? peerGroup;
      for (final g in groups) {
        if (g.userId == widget.peerId) {
          peerGroup = g;
          break;
        }
      }
      if (peerGroup == null || peerGroup.stories.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Сторис недоступна')),
        );
        return;
      }
      final stories = peerGroup.stories;
      final storyIndex = stories.indexWhere((s) => s.id == storyId);
      if (storyIndex == -1) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Эта сторис уже недоступна')),
        );
        return;
      }
      final reorderedStories = [
        ...stories.sublist(storyIndex),
        ...stories.sublist(0, storyIndex),
      ];
      final reorderedGroup = StoryGroupEntity(
        userId: peerGroup.userId,
        stories: reorderedStories,
        userName: peerGroup.userName,
        userAvatarUrl: peerGroup.userAvatarUrl,
      );
      await context.push(
        '/stories',
        extra: StoryViewerArgs(
          groups: [reorderedGroup],
          initialGroupIndex: 0,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть сторис')),
      );
    }
  }
}

class _ReadReceiptTicks extends StatelessWidget {
  const _ReadReceiptTicks({
    required this.readAt,
    required this.outgoingOnPrimary,
  });

  final dynamic readAt;
  final bool outgoingOnPrimary;

  @override
  Widget build(BuildContext context) {
    final read = readAt != null;
    final unreadColor = outgoingOnPrimary
        ? Colors.white.withValues(alpha: 0.72)
        : Colors.black45;
    const readColor = Color(0xFF53BDEB);
    final color = read ? readColor : unreadColor;
    return SizedBox(
      width: 30,
      height: 18,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 1,
            child: Icon(Icons.done, size: 14, color: color),
          ),
          Positioned(
            left: 8,
            top: 1,
            child: Icon(Icons.done, size: 14, color: color),
          ),
        ],
      ),
    );
  }
}

class _DmReactionStrip extends StatelessWidget {
  const _DmReactionStrip({
    required this.rows,
    required this.currentUserId,
    required this.onReactionTap,
    required this.alignEnd,
  });

  final List<Map<String, dynamic>> rows;
  final String currentUserId;
  final ValueChanged<String> onReactionTap;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    final mine = <String>{};
    for (final r in rows) {
      final e = (r['emoji'] ?? '').toString();
      if (e.isEmpty) continue;
      counts[e] = (counts[e] ?? 0) + 1;
      if ((r['user_id'] ?? '').toString() == currentUserId) {
        mine.add(e);
      }
    }
    final keys = counts.keys.toList()..sort();
    return Wrap(
      alignment: alignEnd ? WrapAlignment.end : WrapAlignment.start,
      spacing: 4,
      runSpacing: 4,
      children: keys.map((emoji) {
        final n = counts[emoji]!;
        final isMine = mine.contains(emoji);
        return Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onReactionTap(emoji),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                n > 1 ? '$emoji $n' : emoji,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isMine ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _StoryDirectMessage {
  const _StoryDirectMessage({
    required this.kind,
    required this.storyId,
    required this.previewUrl,
    required this.payload,
  });

  final String kind;
  final String storyId;
  final String previewUrl;
  final String payload;
}

class _PostDirectMessage {
  const _PostDirectMessage({
    required this.postId,
    required this.imageUrl,
    required this.caption,
    required this.authorName,
    required this.videoUrl,
    required this.likesCount,
    required this.commentsCount,
    required this.repostsCount,
  });

  final String postId;
  final String imageUrl;
  final String caption;
  final String authorName;
  final String videoUrl;
  final int likesCount;
  final int commentsCount;
  final int repostsCount;
}

class _StoryLinkedChatBubble extends StatelessWidget {
  const _StoryLinkedChatBubble({
    required this.message,
    required this.isMe,
    required this.onOpenStory,
  });

  final _StoryDirectMessage message;
  final bool isMe;
  final VoidCallback onOpenStory;

  @override
  Widget build(BuildContext context) {
    final textColor = isMe ? Colors.white : Colors.black87;
    final title = message.kind == 'reaction'
        ? 'Реакция на сторис: ${message.payload}'
        : 'Ответ на сторис: ${message.payload}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message.previewUrl.isNotEmpty)
          GestureDetector(
            onTap: onOpenStory,
            child: Container(
              width: 140,
              height: 180,
              margin: const EdgeInsets.only(bottom: 6),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: Colors.black12,
              ),
              child: CachedNetworkImage(
                imageUrl: message.previewUrl,
                fit: BoxFit.cover,
                errorWidget: (_, url, error) => const Center(
                  child: Icon(Icons.broken_image_outlined),
                ),
              ),
            ),
          ),
        Text(
          title,
          style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _PostLinkedChatBubble extends StatelessWidget {
  const _PostLinkedChatBubble({
    required this.message,
    required this.isMe,
    required this.onOpenPost,
    required this.onShare,
    required this.onSave,
  });

  final _PostDirectMessage message;
  final bool isMe;
  final VoidCallback onOpenPost;
  final Future<void> Function() onShare;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context) {
    final textColor = isMe ? Colors.white : Colors.black87;
    final hasPreview = message.imageUrl.isNotEmpty;
    final hasVideo = message.videoUrl.isNotEmpty;
    return GestureDetector(
      onTap: onOpenPost,
      child: SizedBox(
        width: 210,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasPreview)
              Container(
                width: 210,
                height: 240,
                margin: const EdgeInsets.only(bottom: 6),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: Colors.black12,
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: message.imageUrl,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) =>
                          const Center(child: Icon(Icons.broken_image_outlined)),
                    ),
                    if (hasVideo)
                      const Center(
                        child: Icon(
                          Icons.play_circle_fill_rounded,
                          size: 34,
                          color: Colors.white70,
                        ),
                      ),
                  ],
                ),
              ),
            Text(
              message.authorName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (message.caption.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                message.caption,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: textColor),
              ),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                _PostMetricChip(
                  icon: Icons.favorite_border_rounded,
                  value: message.likesCount,
                  color: textColor,
                ),
                const SizedBox(width: 10),
                _PostMetricChip(
                  icon: Icons.mode_comment_outlined,
                  value: message.commentsCount,
                  color: textColor,
                ),
                const SizedBox(width: 10),
                _PostMetricChip(
                  icon: Icons.repeat_rounded,
                  value: message.repostsCount,
                  color: textColor,
                ),
                const Spacer(),
                InkWell(
                  onTap: onShare,
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(Icons.send_outlined, size: 16, color: textColor),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: onSave,
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(Icons.bookmark_border_rounded, size: 16, color: textColor),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PostMetricChip extends StatelessWidget {
  const _PostMetricChip({
    required this.icon,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 3),
        Text(
          _formatCount(value),
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

String _formatCount(int value) {
  if (value >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(1)}M';
  }
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(1)}K';
  }
  return '$value';
}

// ─────────────────────────────────────────────────────────────
// Кнопка микрофона (удерживать для записи)
// ─────────────────────────────────────────────────────────────

class _VoiceMicButton extends StatelessWidget {
  const _VoiceMicButton({
    required this.isRecording,
    required this.seconds,
    required this.onHoldStart,
    required this.onHoldEnd,
    required this.onHoldCancel,
  });

  final bool isRecording;
  final int seconds;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;
  final VoidCallback onHoldCancel;

  String get _timerLabel {
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onLongPressStart: (_) => onHoldStart(),
      onLongPressEnd: (_) => onHoldEnd(),
      onLongPressCancel: onHoldCancel,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: isRecording ? 90 : 48,
        height: 48,
        decoration: BoxDecoration(
          color: isRecording ? Colors.red : primary,
          borderRadius: BorderRadius.circular(24),
        ),
        child: isRecording
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.mic, color: Colors.white, size: 18),
                  const SizedBox(width: 4),
                  Text(
                    _timerLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              )
            : const Icon(Icons.mic_none_rounded, color: Colors.white, size: 22),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Бабл голосового сообщения
// ─────────────────────────────────────────────────────────────

class _VoiceMessageBubble extends StatefulWidget {
  const _VoiceMessageBubble({
    super.key,
    required this.audioUrl,
    required this.durationSeconds,
    required this.isMe,
  });

  final String audioUrl;
  final int durationSeconds;
  final bool isMe;

  @override
  State<_VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<_VoiceMessageBubble> {
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _total = Duration.zero;

  @override
  void initState() {
    super.initState();
    _total = Duration(seconds: widget.durationSeconds);
    _player.onPlayerStateChanged.listen((s) {
      if (!mounted) return;
      setState(() => _playing = s == PlayerState.playing);
    });
    _player.onPositionChanged.listen((p) {
      if (!mounted) return;
      setState(() => _position = p);
    });
    _player.onDurationChanged.listen((d) {
      if (!mounted) return;
      setState(() => _total = d);
    });
    _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() => _position = Duration.zero);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    if (_playing) {
      await _player.pause();
    } else {
      await _player.play(UrlSource(widget.audioUrl));
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(1, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isMe ? Colors.white : Colors.black87;
    final sliderColor =
        widget.isMe ? Colors.white : Theme.of(context).colorScheme.primary;
    final totalSec = _total.inSeconds > 0 ? _total.inSeconds : 1;
    final progress = (_position.inSeconds / totalSec).clamp(0.0, 1.0);

    return SizedBox(
      width: 220,
      child: Row(
        children: [
          GestureDetector(
            onTap: _togglePlayback,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: widget.isMe
                    ? Colors.white24
                    : Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: widget.isMe
                    ? Colors.white
                    : Theme.of(context).colorScheme.primary,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Прогресс-бар (waveform-эффект)
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: widget.isMe
                        ? Colors.white30
                        : Colors.grey.shade300,
                    valueColor: AlwaysStoppedAnimation<Color>(sliderColor),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _playing ? _fmt(_position) : _fmt(_total),
                  style: TextStyle(
                    color: textColor.withValues(alpha: 0.7),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Бабл круглого видео (WhatsApp-стиль)
// ─────────────────────────────────────────────────────────────

class _RoundVideoBubble extends StatefulWidget {
  const _RoundVideoBubble({
    super.key,
    required this.videoUrl,
    required this.isMe,
  });

  final String videoUrl;
  final bool isMe;

  @override
  State<_RoundVideoBubble> createState() => _RoundVideoBubbleState();
}

class _RoundVideoBubbleState extends State<_RoundVideoBubble> {
  VideoPlayerController? _ctrl;
  bool _initialized = false;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    final uri = Uri.tryParse(widget.videoUrl);
    if (uri == null) return;
    final ctrl = VideoPlayerController.networkUrl(uri);
    _ctrl = ctrl;
    try {
      await ctrl.initialize();
      ctrl.setLooping(false);
      ctrl.addListener(_onVideoUpdate);
      if (mounted) setState(() => _initialized = true);
    } catch (_) {}
  }

  void _onVideoUpdate() {
    if (!mounted) return;
    final isPlaying = _ctrl?.value.isPlaying ?? false;
    if (isPlaying != _playing) {
      setState(() => _playing = isPlaying);
    }
  }

  @override
  void dispose() {
    _ctrl?.removeListener(_onVideoUpdate);
    _ctrl?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final ctrl = _ctrl;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (ctrl.value.isPlaying) {
      ctrl.pause();
    } else {
      if (ctrl.value.position >= ctrl.value.duration) {
        ctrl.seekTo(Duration.zero);
      }
      ctrl.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    const size = 180.0;
    return GestureDetector(
      onTap: _togglePlay,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            ClipOval(
              child: _initialized && _ctrl != null
                  ? AspectRatio(
                      aspectRatio: 1,
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: _ctrl!.value.size.width,
                          height: _ctrl!.value.size.height,
                          child: VideoPlayer(_ctrl!),
                        ),
                      ),
                    )
                  : Container(
                      width: size,
                      height: size,
                      color: Colors.black87,
                      child: const Center(
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      ),
                    ),
            ),
            // Кнопка play/pause поверх видео
            if (_initialized && !_playing)
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.black45,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
            // Прогресс поверх кольца
            if (_initialized && _ctrl != null)
              SizedBox.expand(
                child: ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: _ctrl!,
                  builder: (_, val, unused) {
                    final total = val.duration.inMilliseconds;
                    final pos = val.position.inMilliseconds;
                    final progress =
                        total > 0 ? (pos / total).clamp(0.0, 1.0) : 0.0;
                    return CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        widget.isMe
                            ? Colors.white
                            : Theme.of(context).colorScheme.primary,
                      ),
                      backgroundColor: Colors.white30,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// _ChatIconBtn — маленькая кнопка иконки в input bar
// ══════════════════════════════════════════════════════════════

class _ChatIconBtn extends StatelessWidget {
  const _ChatIconBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 24,
              color: Theme.of(context).colorScheme.primary),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// _SendBtn — кнопка отправки
// ══════════════════════════════════════════════════════════════

class _SendBtn extends StatelessWidget {
  const _SendBtn({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.send_rounded,
            color: Colors.white, size: 20),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// _AttachmentSheet — WhatsApp-стиль панель вложений
// ══════════════════════════════════════════════════════════════

class _AttachmentSheet extends StatelessWidget {
  const _AttachmentSheet({
    required this.onPhoto,
    required this.onCamera,
    required this.onLocation,
    required this.onContact,
    required this.onDocument,
    required this.onPoll,
    required this.onEvent,
  });

  final VoidCallback onPhoto;
  final VoidCallback onCamera;
  final VoidCallback onLocation;
  final VoidCallback onContact;
  final VoidCallback onDocument;
  final VoidCallback onPoll;
  final VoidCallback onEvent;

  @override
  Widget build(BuildContext context) {
    final items = [
      _AttachItem(Icons.photo_library_rounded, 'Фото', const Color(0xFF8B5CF6), onPhoto),
      _AttachItem(Icons.camera_alt_rounded, 'Камера', const Color(0xFFEC4899), onCamera),
      _AttachItem(Icons.location_on_rounded, 'Местополо-жение', const Color(0xFF10B981), onLocation),
      _AttachItem(Icons.person_rounded, 'Контакт', const Color(0xFF3B82F6), onContact),
      _AttachItem(Icons.insert_drive_file_rounded, 'Документ', const Color(0xFFF59E0B), onDocument),
      _AttachItem(Icons.bar_chart_rounded, 'Опрос', const Color(0xFF06B6D4), onPoll),
      _AttachItem(Icons.event_rounded, 'Мероприятие', const Color(0xFFEF4444), onEvent),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 16,
                crossAxisSpacing: 8,
                childAspectRatio: 0.82,
                children: items.map((item) {
                  return GestureDetector(
                    onTap: item.onTap,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: item.color.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(item.icon,
                              color: item.color, size: 28),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.label,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachItem {
  const _AttachItem(this.icon, this.label, this.color, this.onTap);
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
}

// ══════════════════════════════════════════════════════════════
// _EmojiPanel — панель эмодзи / GIF / стикеров
// ══════════════════════════════════════════════════════════════

class _EmojiPanel extends StatefulWidget {
  const _EmojiPanel({
    required this.onEmojiSelected,
    required this.onGifSelected,
  });
  final ValueChanged<String> onEmojiSelected;
  final ValueChanged<String> onGifSelected;

  @override
  State<_EmojiPanel> createState() => _EmojiPanelState();
}

class _EmojiPanelState extends State<_EmojiPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  int _categoryIndex = 0;

  static const _categories = [
    ('😀', 'Смайлы'),
    ('🙌', 'Жесты'),
    ('❤️', 'Сердца'),
    ('🐶', 'Животные'),
    ('🍕', 'Еда'),
    ('⚽', 'Спорт'),
    ('✈️', 'Путешествия'),
  ];

  static const _emojiByCat = [
    // Смайлы
    ['😀','😃','😄','😁','😆','😅','🤣','😂','🙂','🙃','😉','😊','😇','🥰','😍','🤩','😘','😗','😚','😙','🥲','😋','😛','😜','🤪','😝','🤑','🤗','🤭','🤫','🤔','🤐','🤨','😐','😑','😶','😏','😒','🙄','😬','🤥','😌','😔','😪','🤤','😴','😷','🤒','🤕','🤢','🤧','🥵','🥶','🥴','😵','🤯','🤠','🥳','😎','🤓','🧐','😕','😟','🙁','☹️','😮','😯','😲','😳','🥺','😦','😧','😨','😰','😥','😢','😭','😱','😖','😣','😞','😓','😩','😫','🥱'],
    // Жесты
    ['👋','🤚','🖐','✋','🖖','👌','🤌','🤏','✌️','🤞','🤟','🤘','🤙','👈','👉','👆','🖕','👇','☝️','👍','👎','✊','👊','🤛','🤜','👏','🙌','👐','🤲','🤝','🙏','✍️','💅','🤳','💪','🦾','🦿','🦵','🦶','👂','🦻','👃','🫀','🫁','🧠','🦷','🦴','👀','👁','👅','👄'],
    // Сердца
    ['❤️','🧡','💛','💚','💙','💜','🖤','🤍','🤎','💔','❣️','💕','💞','💓','💗','💖','💘','💝','💟','☮️','✝️','☪️','🕉','✡️','🔯','🛐','⛎','♈','♉','♊','♋','♌','♍','♎','♏','♐','♑','♒','♓','🆔','⚛️','🉑','☢️','☣️','📴','📳','🈶','🈚','🈸','🈺','🈷️','✴️','🆚','💮','🉐','㊙️','㊗️','🈴','🈵','🈹','🈲','🅰️','🅱️','🆎','🆑','🅾️','🆘','❌','⭕','🛑','⛔','📛','🚫'],
    // Животные
    ['🐶','🐱','🐭','🐹','🐰','🦊','🐻','🐼','🐨','🐯','🦁','🐮','🐷','🐸','🐵','🙈','🙉','🙊','🐒','🐔','🐧','🐦','🐤','🦆','🦅','🦉','🦇','🐺','🐗','🐴','🦄','🐝','🪱','🐛','🦋','🐌','🐞','🐜','🪲','🦟','🦗','🕷','🦂','🐢','🐍','🦎','🦖','🦕','🐙','🦑','🦐','🦞','🦀','🐡','🐠','🐟','🐬','🐳','🐋','🦈','🦭','🐊','🐅','🐆','🦓','🦍','🦧','🦣','🐘','🦛','🦏','🐪','🐫','🦒','🦘','🦬','🐃','🐂','🐄','🐎','🐖','🐏','🐑','🦙','🐐','🦌','🐕','🐩','🦮','🐕‍🦺','🐈','🐈‍⬛','🪶','🐓','🦃','🦤','🦚','🦜','🦢','🦩','🕊','🐇','🦝','🦨','🦡','🦫','🦦','🦥','🐁','🐀','🐿','🦔'],
    // Еда
    ['🍏','🍎','🍐','🍊','🍋','🍌','🍉','🍇','🍓','🫐','🍈','🍒','🍑','🥭','🍍','🥥','🥝','🍅','🍆','🥑','🥦','🥬','🥒','🌶','🫑','🧄','🧅','🥔','🍠','🥐','🥯','🍞','🥖','🥨','🧀','🥚','🍳','🧈','🥞','🧇','🥓','🥩','🍗','🍖','🌭','🍔','🍟','🍕','🫓','🥪','🥙','🧆','🌮','🌯','🫔','🥗','🥘','🫕','🥫','🍝','🍜','🍲','🍛','🍣','🍱','🥟','🦪','🍤','🍙','🍚','🍘','🍥','🥮','🍢','🧁','🍰','🎂','🍮','🍭','🍬','🍫','🍿','🍩','🍪','🌰','🥜','🍯','🧃','🥤','🧋','🍵','☕','🫖','🍺','🍻','🥂','🍷','🥃','🍸','🍹','🧉','🍾','🧊','🥄','🍴','🍽','🥢','🧂'],
    // Спорт
    ['⚽','🏀','🏈','⚾','🥎','🎾','🏐','🏉','🥏','🎱','🪀','🏓','🏸','🏒','🥍','🏏','🪃','🥅','⛳','🪁','🎣','🤿','🎽','🎿','🛷','🥌','🎯','🪀','🎮','🎲','♟','🎭','🎨','🎬','🎤','🎧','🎼','🎹','🥁','🪘','🎷','🎺','🎸','🪕','🎻','🎲','♟','🎯','🎳','🎰','🎪'],
    // Путешествия
    ['✈️','🚀','🛸','🚁','🛶','⛵','🚤','🛥','🛳','⛴','🚢','🚂','🚃','🚄','🚅','🚆','🚇','🚈','🚉','🚊','🚝','🚞','🚋','🚌','🚍','🚎','🏎','🚓','🚑','🚒','🚐','🛻','🚚','🚛','🚜','🏍','🛵','🛺','🚲','🛴','🛹','🛼','🛤','⛽','🚨','🚥','🚦','🛑','🏔','⛰','🌋','🗻','🏕','🏖','🏗','🏘','🏙','🏚','🏛','🏟','🏠','🏡','🏢','🏣','🏤','🏥','🏦','🏧','🏨','🏩','🏪','🏫','🏬','🏭','🏯','🏰','💒','🗼','🗽','⛪','🕌','🛕','🕍','⛩','🕋'],
  ];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 300,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        children: [
          // Tabs
          TabBar(
            controller: _tab,
            labelColor: Theme.of(context).colorScheme.primary,
            unselectedLabelColor: Colors.grey.shade500,
            indicatorSize: TabBarIndicatorSize.tab,
            tabs: const [
              Tab(text: 'Эмодзи'),
              Tab(text: 'GIF'),
              Tab(text: 'Стикеры'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                // ── Эмодзи ──
                Column(
                  children: [
                    // Категории
                    SizedBox(
                      height: 42,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        itemCount: _categories.length,
                        itemBuilder: (_, i) {
                          final selected = i == _categoryIndex;
                          return GestureDetector(
                            onTap: () =>
                                setState(() => _categoryIndex = i),
                            child: AnimatedContainer(
                              duration:
                                  const Duration(milliseconds: 150),
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: selected
                                    ? Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withValues(alpha: 0.12)
                                    : Colors.transparent,
                                borderRadius:
                                    BorderRadius.circular(16),
                              ),
                              child: Text(
                                _categories[i].$1,
                                style: const TextStyle(fontSize: 20),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    // Эмодзи грид
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.all(8),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 8,
                          childAspectRatio: 1,
                        ),
                        itemCount:
                            _emojiByCat[_categoryIndex].length,
                        itemBuilder: (_, i) {
                          final emoji =
                              _emojiByCat[_categoryIndex][i];
                          return GestureDetector(
                            onTap: () =>
                                widget.onEmojiSelected(emoji),
                            child: Center(
                              child: Text(emoji,
                                  style: const TextStyle(
                                      fontSize: 24)),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                // ── GIF ──
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🎬', style: TextStyle(fontSize: 48)),
                      const SizedBox(height: 12),
                      Text(
                        'GIF — скоро',
                        style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 15),
                      ),
                    ],
                  ),
                ),
                // ── Стикеры ──
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🎭', style: TextStyle(fontSize: 48)),
                      const SizedBox(height: 12),
                      Text(
                        'Стикеры — скоро',
                        style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 15),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// _ImageMessageBubble — пузырь с изображением
// ══════════════════════════════════════════════════════════════

class _ImageMessageBubble extends StatelessWidget {
  const _ImageMessageBubble({
    super.key,
    required this.imageUrl,
    required this.isLocal,
    required this.isMe,
    required this.isPending,
  });

  final String imageUrl;
  final bool isLocal;
  final bool isMe;
  final bool isPending;

  @override
  Widget build(BuildContext context) {
    const radius = Radius.circular(16);
    final borderRadius = isMe
        ? const BorderRadius.only(
            topLeft: radius,
            topRight: radius,
            bottomLeft: radius,
            bottomRight: Radius.circular(4),
          )
        : const BorderRadius.only(
            topLeft: radius,
            topRight: radius,
            bottomLeft: Radius.circular(4),
            bottomRight: radius,
          );

    return ClipRRect(
      borderRadius: borderRadius,
      child: Stack(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(
                maxWidth: 220, maxHeight: 280, minWidth: 120),
            child: isLocal
                ? Image.file(
                    File(imageUrl),
                    fit: BoxFit.cover,
                    width: 220,
                  )
                : CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    width: 220,
                    placeholder: (ctx, url2) => Container(
                      width: 220,
                      height: 160,
                      color: Colors.grey.shade200,
                      child: const Center(
                          child: CircularProgressIndicator()),
                    ),
                    errorWidget: (ctx, url2, err) => Container(
                      width: 220,
                      height: 100,
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.broken_image_rounded,
                          color: Colors.grey),
                    ),
                  ),
          ),
          if (isPending)
            Positioned(
              bottom: 6,
              right: 8,
              child: Icon(Icons.access_time_rounded,
                  size: 14, color: Colors.white.withValues(alpha: 0.8)),
            ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// _LocationBubble — пузырь с местоположением
// ══════════════════════════════════════════════════════════════

class _LocationBubble extends StatelessWidget {
  const _LocationBubble({
    super.key,
    required this.lat,
    required this.lng,
    required this.isMe,
  });

  final double lat;
  final double lng;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Координаты: $lat, $lng'),
          action: SnackBarAction(
            label: 'Скопировать',
            onPressed: () => Clipboard.setData(
                ClipboardData(text: '$lat,$lng')),
          ),
          behavior: SnackBarBehavior.floating,
        ));
      },
      child: Container(
        width: 200,
        height: 100,
        decoration: BoxDecoration(
          color: isMe
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isMe
                  ? Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.3)
                  : Colors.grey.shade300),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            Icon(Icons.location_on_rounded,
                color: Colors.red.shade400, size: 32),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Местоположение',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(
                    '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade600),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
