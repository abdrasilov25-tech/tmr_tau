import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:camera/camera.dart';

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
import '../widgets/dm_hold_video_overlay.dart';

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
  /// Полоса реакций как в WhatsApp (плюс кнопка «ещё» открывает сетку).
  static const List<String> _waBarReactionEmojis = [
    '👍',
    '❤️',
    '😂',
    '😮',
    '😢',
    '🙏',
    '🔥',
  ];

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

  /// Ответ на сообщение (reply_to на сервере).
  String? _replyingToMessageId;
  String? _replyingToSnippet;

  // ── Голосовые сообщения ────────────────────────────────────
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecordingVoice = false;
  int _voiceRecordSeconds = 0;
  Timer? _voiceTimer;
  // Переключение кнопки send/mic/camera в зависимости от ввода
  final ValueNotifier<bool> _textHasContent = ValueNotifier<bool>(false);

  /// Удержание кнопки видеокружка → через [ _videoCircleArmMs ] открывается запись.
  Timer? _videoCircleArmTimer;
  bool _dmVideoOpening = false;
  static const int _videoCircleArmMs = 220;

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
    _videoCircleArmTimer?.cancel();
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

  void _cancelDmVideoCircleArm() {
    _videoCircleArmTimer?.cancel();
    _videoCircleArmTimer = null;
  }

  void _scheduleDmVideoCircleIfHeld() {
    _cancelDmVideoCircleArm();
    _videoCircleArmTimer = Timer(
      const Duration(milliseconds: _videoCircleArmMs),
      () {
        if (!mounted) return;
        unawaited(_runDmVideoCircleRecorder());
      },
    );
  }

  String _userFacingChatStorageError(Object e) {
    if (e is StorageException) {
      final m = e.message.toLowerCase();
      if (m.contains('bucket') && m.contains('not found')) {
        return 'Хранилище чата не настроено на сервере (бакет messages).';
      }
      return 'Не удалось загрузить файл. Проверьте соединение.';
    }
    return 'Попробуйте ещё раз через минуту.';
  }

  Future<void> _showSoftChatDialog({
    required String title,
    required String message,
  }) async {
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.info_outline_rounded, color: cs.primary),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      height: 1.4,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Понятно'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _runDmVideoCircleRecorder() async {
    if (_dmVideoOpening || _sending) return;
    final uid = _me();
    if (uid == null || !mounted) return;

    var cam = await Permission.camera.status;
    if (cam.isPermanentlyDenied) {
      await _showSoftChatDialog(
        title: 'Нужна камера',
        message:
            'Чтобы записать видеокружок, разрешите доступ к камере в настройках устройства.',
      );
      return;
    }
    if (!cam.isGranted) {
      cam = await Permission.camera.request();
      if (!cam.isGranted) return;
    }
    var mic = await Permission.microphone.status;
    if (mic.isPermanentlyDenied) {
      await _showSoftChatDialog(
        title: 'Нужен микрофон',
        message:
            'Для видеокружка со звуком разрешите микрофон в настройках устройства.',
      );
      return;
    }
    if (!mic.isGranted) {
      mic = await Permission.microphone.request();
      if (!mic.isGranted) return;
    }

    final cams = await availableCameras();
    if (cams.isEmpty) {
      if (!mounted) return;
      await _showSoftChatDialog(
        title: 'Камера недоступна',
        message:
            'На этом устройстве нет камеры (например, симулятор) или она занята другим приложением.',
      );
      return;
    }

    if (!mounted) return;
    _dmVideoOpening = true;
    try {
      final result = await Navigator.of(context).push<DmHoldVideoResult>(
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
      if (result == null || !mounted) return;
      await _uploadDmVideoCircleFromFile(result.file, uid);
    } finally {
      _dmVideoOpening = false;
    }
  }

  Future<void> _uploadDmVideoCircleFromFile(File file, String uid) async {
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
    final mime = _videoContentTypeForPath(p);

    setState(() => _sending = true);
    try {
      final bytes = await file.readAsBytes();
      final uploadPath =
          'dm/$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';
      await _client.storage.from(SupabaseConstants.bucketChatMedia).uploadBinary(
            uploadPath,
            bytes,
            fileOptions: FileOptions(contentType: mime, upsert: false),
          );
      final url = _client.storage
          .from(SupabaseConstants.bucketChatMedia)
          .getPublicUrl(uploadPath);
      await _client.from(SupabaseConstants.messagesTable).insert({
        'sender_id': uid,
        'receiver_id': widget.peerId,
        'text': '',
        'message_type': 'video_circle',
        'video_url': url,
        'duration_seconds': durationSec,
      });
      _forceScrollToLatest = true;
    } catch (e) {
      if (!mounted) return;
      await _showSoftChatDialog(
        title: 'Не отправилось',
        message: _userFacingChatStorageError(e),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
      try {
        await file.delete();
      } catch (_) {}
    }
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
    final imageUrl = source['image_url'] as String?;
    final fileUrl = source['file_url'] as String?;
    final fileName = source['file_name'] as String?;
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
      if (imageUrl != null && imageUrl.isNotEmpty) {
        row['image_url'] = imageUrl;
      }
      if (fileUrl != null && fileUrl.isNotEmpty) {
        row['file_url'] = fileUrl;
      }
      if (fileName != null && fileName.isNotEmpty) {
        row['file_name'] = fileName;
      }
      final replyTo = source['reply_to'] as String?;
      if (replyTo != null && replyTo.isNotEmpty) {
        row['reply_to'] = replyTo;
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

  String _dmMessageSnippetForActions(Map<String, dynamic> m) {
    final type = (m['message_type'] as String?) ?? 'text';
    final raw = m['text'] as String? ?? '';
    switch (type) {
      case 'image':
        return '📷 Фото';
      case 'gif':
        return 'GIF';
      case 'audio':
        return '🎤 Голосовое сообщение';
      case 'video_circle':
        return '📹 Видеосообщение';
      case 'file':
        final n = (m['file_name'] as String?)?.trim();
        return (n != null && n.isNotEmpty) ? '📎 $n' : '📎 Файл';
      case 'event':
        return '📅 Мероприятие';
      case 'location':
        return '📍 Геолокация';
      default:
        break;
    }
    if (raw.isEmpty) return 'Сообщение';
    if (raw.startsWith(_storyDmPrefix)) return 'Сторис';
    if (raw.startsWith(_postDmPrefix)) return 'Публикация';
    if (raw.length > 200) return '${raw.substring(0, 197)}…';
    return raw;
  }

  String _messageShortTime(dynamic createdAt) {
    final t = _parseTs(createdAt);
    if (t == null) return '';
    final l = t.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:'
        '${l.minute.toString().padLeft(2, '0')}';
  }

  List<String> _allPickableReactionEmojis() {
    final set = <String>{
      ..._waBarReactionEmojis,
      ..._quickReactionEmojis,
      '🫶',
      '🤝',
      '💯',
      '✨',
      '⭐',
      '🎉',
      '💪',
      '😍',
      '🥰',
      '😘',
      '🤩',
      '🙌',
      '👋',
      '✌️',
      '👌',
      '😊',
      '😉',
      '😭',
      '🤔',
      '😱',
      '💔',
      '🖤',
      '💋',
      '🎂',
      '☀️',
      '☕',
      '🍕',
      '⚽',
      '✈️',
      '🏠',
    };
    return set.toList(growable: false);
  }

  void _showExtendedReactionEmojisForDm(
    BuildContext dialogContext,
    String messageId,
  ) {
    final emojis = _allPickableReactionEmojis();
    showModalBottomSheet<void>(
      context: dialogContext,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.48,
          minChildSize: 0.32,
          maxChildSize: 0.88,
          builder: (_, scrollCtrl) {
            return Material(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(18)),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Text(
                    'Выберите реакцию',
                    style: Theme.of(sheetContext).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: GridView.builder(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 8,
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 6,
                      ),
                      itemCount: emojis.length,
                      itemBuilder: (_, i) {
                        final e = emojis[i];
                        return InkWell(
                          onTap: () {
                            Navigator.pop(sheetContext);
                            Navigator.pop(dialogContext);
                            unawaited(_setReactionForMessage(messageId, e));
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Center(
                            child: Text(e, style: const TextStyle(fontSize: 28)),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDeleteOrHideDm(
    Map<String, dynamic> m,
    String messageId,
    bool isMine,
  ) async {
    final uid = _me();
    if (uid == null) return;
    final chatStorage = context.read<ChatListStorage>();
    final unreadController = context.read<ChatUnreadBadgeController>();
    if (isMine) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Удалить сообщение?'),
          content: const Text(
            'Сообщение будет удалено у всех. Это действие нельзя отменить.',
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
      if (ok != true || !mounted) return;
      try {
        await _client
            .from(SupabaseConstants.messagesTable)
            .delete()
            .eq('id', messageId)
            .or(
              'and(sender_id.eq.$uid,receiver_id.eq.${widget.peerId}),'
              'and(sender_id.eq.${widget.peerId},receiver_id.eq.$uid)',
            );
        if (!mounted) return;
        setState(() {});
        unreadController.refresh();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Сообщение удалено')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось удалить: $e')),
        );
      }
    } else {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Скрыть сообщение?'),
          content: const Text(
            'Сообщение будет скрыто только у вас в этом чате.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Скрыть'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      await chatStorage.addHiddenMessageIds(widget.peerId, [messageId]);
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сообщение скрыто')),
      );
    }
  }

  void _showDmMoreActionsSheet(
    Map<String, dynamic> m,
    String messageId,
    bool canCopy,
  ) {
    final text = (m['text'] as String?) ?? '';
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
              title: const Text('Другие реакции'),
              onTap: () {
                Navigator.pop(ctx);
                _showReactionPickerSheet(messageId);
              },
            ),
            ListTile(
              leading: const Icon(Icons.checklist_rtl_outlined),
              title: const Text('Выбрать несколько'),
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

  void _showWhatsAppStyleMessageMenu(
    Map<String, dynamic> m,
    String messageId,
  ) {
    final me = _me();
    if (me == null || messageId.isEmpty) return;
    final isMine = (m['sender_id'] as String?) == me;
    final text = (m['text'] as String?) ?? '';
    final msgType = (m['message_type'] as String?) ?? 'text';
    final canCopy = text.trim().isNotEmpty &&
        !text.startsWith(_storyDmPrefix) &&
        !text.startsWith(_postDmPrefix) &&
        msgType != 'location' &&
        msgType != 'event' &&
        msgType != 'file' &&
        msgType != 'image' &&
        msgType != 'gif' &&
        msgType != 'audio' &&
        msgType != 'video_circle';
    final snippet = _dmMessageSnippetForActions(m);
    final timeLabel = _messageShortTime(m['created_at']);
    final chatStorage = context.read<ChatListStorage>();

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOut,
          ),
          child: StatefulBuilder(
            builder: (ctx, setModalState) {
              final starred =
                  chatStorage.isDmMessageStarred(widget.peerId, messageId);
              return Material(
                color: Colors.transparent,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => Navigator.pop(dialogContext),
                        child: ClipRect(
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                            child: Container(
                              color: Colors.black.withValues(alpha: 0.28),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SafeArea(
                      child: Column(
                        children: [
                          const Spacer(flex: 2),
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 20),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 16,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (final e in _waBarReactionEmojis)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4),
                                      child: InkWell(
                                        onTap: () {
                                          Navigator.pop(dialogContext);
                                          unawaited(
                                              _setReactionForMessage(
                                                  messageId, e));
                                        },
                                        borderRadius: BorderRadius.circular(20),
                                        child: Padding(
                                          padding: const EdgeInsets.all(6),
                                          child: Text(
                                            e,
                                            style:
                                                const TextStyle(fontSize: 28),
                                          ),
                                        ),
                                      ),
                                    ),
                                  Material(
                                    color: Colors.grey.shade200,
                                    shape: const CircleBorder(),
                                    child: InkWell(
                                      customBorder: const CircleBorder(),
                                      onTap: () => _showExtendedReactionEmojisForDm(
                                        dialogContext,
                                        messageId,
                                      ),
                                      child: const Padding(
                                        padding: EdgeInsets.all(10),
                                        child: Icon(Icons.add, size: 22),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 24),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 340),
                              child: Container(
                                padding: const EdgeInsets.fromLTRB(
                                    14, 12, 14, 10),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 12,
                                      offset: Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      snippet,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        height: 1.35,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: Text(
                                        timeLabel,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const Spacer(flex: 3),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                            child: Material(
                              color: Theme.of(ctx).colorScheme.surface,
                              elevation: 8,
                              shadowColor: Colors.black26,
                              borderRadius: BorderRadius.circular(16),
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ListTile(
                                    leading: const Icon(Icons.reply_rounded),
                                    title: const Text('Ответить'),
                                    onTap: () {
                                      Navigator.pop(dialogContext);
                                      if (messageId.startsWith('tmp_')) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Дождитесь отправки сообщения',
                                            ),
                                          ),
                                        );
                                        return;
                                      }
                                      setState(() {
                                        _replyingToMessageId = messageId;
                                        _replyingToSnippet = snippet;
                                      });
                                    },
                                  ),
                                  ListTile(
                                    leading:
                                        const Icon(Icons.forward_rounded),
                                    title: const Text('Переслать'),
                                    onTap: () {
                                      Navigator.pop(dialogContext);
                                      unawaited(_openForwardPeerPicker(m));
                                    },
                                  ),
                                  if (canCopy)
                                    ListTile(
                                      leading: const Icon(Icons.copy_rounded),
                                      title: const Text('Копировать'),
                                      onTap: () async {
                                        Navigator.pop(dialogContext);
                                        await Clipboard.setData(
                                            ClipboardData(text: text));
                                        if (mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content: Text('Скопировано'),
                                            ),
                                          );
                                        }
                                      },
                                    ),
                                  ListTile(
                                    leading: Icon(
                                      starred
                                          ? Icons.star_rounded
                                          : Icons.star_outline_rounded,
                                      color: starred
                                          ? Theme.of(ctx).colorScheme.primary
                                          : null,
                                    ),
                                    title: Text(
                                      starred
                                          ? 'Убрать из избранного'
                                          : 'В избранное',
                                    ),
                                    onTap: () async {
                                      final messenger =
                                          ScaffoldMessenger.of(context);
                                      await chatStorage.toggleStarredDmMessage(
                                        widget.peerId,
                                        messageId,
                                      );
                                      setModalState(() {});
                                      if (!mounted) return;
                                      final now = chatStorage
                                          .isDmMessageStarred(
                                              widget.peerId, messageId);
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            now
                                                ? 'Добавлено в избранное'
                                                : 'Убрано из избранного',
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  ListTile(
                                    leading: const Icon(
                                      Icons.delete_outline_rounded,
                                      color: Colors.red,
                                    ),
                                    title: const Text(
                                      'Удалить',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                    onTap: () {
                                      Navigator.pop(dialogContext);
                                      unawaited(_confirmDeleteOrHideDm(
                                        m,
                                        messageId,
                                        isMine,
                                      ));
                                    },
                                  ),
                                  const Divider(height: 1),
                                  ListTile(
                                    leading: const Icon(Icons.more_horiz_rounded),
                                    title: const Text('Ещё…'),
                                    onTap: () {
                                      Navigator.pop(dialogContext);
                                      _showDmMoreActionsSheet(
                                        m,
                                        messageId,
                                        canCopy,
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
              );
            },
          ),
        );
      },
    );
  }

  void _showDirectMessageActions(Map<String, dynamic> m, String messageId) {
    FocusScope.of(context).unfocus();
    _showWhatsAppStyleMessageMenu(m, messageId);
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

    final replyToId = _replyingToMessageId;
    final replySnippet = _replyingToSnippet;
    final replyToValid = replyToId != null &&
        replyToId.isNotEmpty &&
        !replyToId.startsWith('tmp_');

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
      if (replyToValid) 'reply_to': replyToId,
    };
    setState(() {
      _optimisticMessages.add(optimistic);
      _sending = true;
      _replyingToMessageId = null;
      _replyingToSnippet = null;
    });
    // Очищаем поле и скроллим сразу — не ждём сервер
    _controller.clear();
    _textHasContent.value = false;
    _forceScrollToLatest = true;
    // ─────────────────────────────────────────────────────────

    try {
      final insertPayload = <String, dynamic>{
        'sender_id': uid,
        'receiver_id': widget.peerId,
        'text': text,
        if (replyToValid) 'reply_to': replyToId,
      };
      final inserted = await _client
          .from(SupabaseConstants.messagesTable)
          .insert(insertPayload)
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
        if (replyToValid) {
          _replyingToMessageId = replyToId;
          _replyingToSnippet = replySnippet;
        }
      });
      _controller.text = text;
      _textHasContent.value = text.trim().isNotEmpty;
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
                          final fileUrl = m['file_url'] as String?;
                          final fileName = (m['file_name'] as String?) ?? '';
                          final isLocalImage = m['_local'] == true;
                          final durationSec = (m['duration_seconds'] as int?) ?? 0;
                          final structured = _parseStoryDirectMessage(text);
                          final postStructured = _parsePostDirectMessage(text);
                          final locationData =
                              _parseLocationMessage(text, msgType);
                          final eventData =
                              _parseEventPayload(text, msgType);
                          final replyToRaw = m['reply_to'];
                          final replyToId = replyToRaw is String
                              ? replyToRaw.trim()
                              : '';
                          String? replyQuote;
                          if (replyToId.isNotEmpty) {
                            Map<String, dynamic>? parent;
                            for (final x in messages) {
                              if ((x['id'] ?? '').toString() == replyToId) {
                                parent = x;
                                break;
                              }
                            }
                            replyQuote = parent != null
                                ? _dmMessageSnippetForActions(parent)
                                : 'Сообщение';
                          }
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
                              onTap: () {
                                if (_selectionMode) {
                                  _toggleMessageSelection(messageId);
                                } else {
                                  _showDirectMessageActions(m, messageId);
                                }
                              },
                              onLongPress: () {
                                if (_selectionMode) {
                                  _toggleMessageSelection(messageId);
                                } else {
                                  _showDirectMessageActions(m, messageId);
                                }
                              },
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
                                    if (replyQuote != null)
                                      Container(
                                        width: double.infinity,
                                        margin:
                                            const EdgeInsets.only(bottom: 8),
                                        padding: const EdgeInsets.fromLTRB(
                                            10, 8, 10, 8),
                                        decoration: BoxDecoration(
                                          color: isMe
                                              ? Colors.white
                                                  .withValues(alpha: 0.22)
                                              : Colors.black
                                                  .withValues(alpha: 0.06),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          border: Border(
                                            left: BorderSide(
                                              color: isMe
                                                  ? Colors.white70
                                                  : Theme.of(context)
                                                      .colorScheme
                                                      .primary,
                                              width: 3,
                                            ),
                                          ),
                                        ),
                                        child: Text(
                                          replyQuote,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13,
                                            height: 1.25,
                                            color: isMe
                                                ? Colors.white.withValues(
                                                    alpha: 0.95)
                                                : Colors.black87,
                                          ),
                                        ),
                                      ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Flexible(
                                          child: msgType == 'gif' &&
                                                  imageUrl != null
                                              ? _GifMessageBubble(
                                                  key: ValueKey('gif_$messageId'),
                                                  gifUrl: imageUrl,
                                                  isMe: isMe,
                                                )
                                              : msgType == 'image' &&
                                                  imageUrl != null
                                              ? _ImageMessageBubble(
                                                  key: ValueKey('img_$messageId'),
                                                  imageUrl: imageUrl,
                                                  isLocal: isLocalImage,
                                                  isMe: isMe,
                                                  isPending: m['_pending'] == true,
                                                )
                                              : msgType == 'file' &&
                                                      fileUrl != null &&
                                                      fileUrl.isNotEmpty
                                                  ? _FileMessageBubble(
                                                      key: ValueKey(
                                                          'file_$messageId'),
                                                      fileUrl: fileUrl,
                                                      fileName: fileName,
                                                      isMe: isMe,
                                                    )
                                                  : msgType == 'event' &&
                                                          eventData != null
                                                      ? _EventMessageBubble(
                                                          key: ValueKey(
                                                              'evt_$messageId'),
                                                          title: eventData.title,
                                                          when: eventData.when,
                                                          place: eventData.place,
                                                          isMe: isMe,
                                                        )
                                                      : locationData != null
                                                          ? _LocationBubble(
                                                              key: ValueKey(
                                                                  'loc_$messageId'),
                                                              lat: locationData.lat,
                                                              lng: locationData.lng,
                                                              address: locationData.address,
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
                        if (_replyingToMessageId != null)
                          Material(
                            color: ThemedContentSurface.scaffoldElevated,
                            elevation: 1,
                            shadowColor: Colors.black12,
                            child: ListTile(
                              dense: true,
                              leading: Icon(
                                Icons.reply_rounded,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              title: Text(
                                _replyingToSnippet ?? '',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () => setState(() {
                                  _replyingToMessageId = null;
                                  _replyingToSnippet = null;
                                }),
                              ),
                            ),
                          ),
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
                                    setState(() => _showEmojiPanel = false);
                                    _sendImageUrl(url, isGif: true);
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
                                        // 🎬 Видеокружок (удерживать)
                                        _VideoCircleHoldButton(
                                          onHoldArm:
                                              _scheduleDmVideoCircleIfHeld,
                                          onHoldDisarm:
                                              _cancelDmVideoCircleArm,
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
    if (status.isPermanentlyDenied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Разрешите микрофон в Настройках'),
          action: SnackBarAction(label: 'Открыть', onPressed: openAppSettings),
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }
    if (!status.isGranted && !status.isLimited) return;
    if (!mounted) return;
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
      final uploadPath =
          'dm/$uid/${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _client.storage
          .from(SupabaseConstants.bucketChatMedia)
          .uploadBinary(
            uploadPath,
            bytes,
            fileOptions:
                const FileOptions(contentType: 'audio/m4a', upsert: false),
          );
      final url = _client.storage
          .from(SupabaseConstants.bucketChatMedia)
          .getPublicUrl(uploadPath);
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
      await _showSoftChatDialog(
        title: 'Голосовое не отправилось',
        message: _userFacingChatStorageError(e),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  static String _videoContentTypeForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.3gp')) return 'video/3gpp';
    return 'video/mp4';
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
        onVoice: () {
          Navigator.pop(sheetCtx);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Удерживайте кнопку микрофона справа от поля ввода, чтобы записать голосовое.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        onRoundVideo: () {
          Navigator.pop(sheetCtx);
          unawaited(_runDmVideoCircleRecorder());
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
          unawaited(_pickAndSendDocument());
        },
        onPoll: () {
          Navigator.pop(sheetCtx);
          _showComingSoon('Опросы');
        },
        onEvent: () {
          Navigator.pop(sheetCtx);
          _showEventComposer();
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
          'dm/$uid/img_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await _client.storage
          .from(SupabaseConstants.bucketChatMedia)
          .uploadBinary(
            uploadPath,
            bytes,
            fileOptions:
                FileOptions(contentType: 'image/$ext', upsert: false),
          );
      final url = _client.storage
          .from(SupabaseConstants.bucketChatMedia)
          .getPublicUrl(uploadPath);
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

  Future<void> _sendImageUrl(String url, {bool isGif = false}) async {
    final uid = _me();
    if (uid == null) return;
    try {
      await _client.from(SupabaseConstants.messagesTable).insert({
        'sender_id': uid,
        'receiver_id': widget.peerId,
        'text': '',
        'message_type': isGif ? 'gif' : 'image',
        'image_url': url,
      });
      if (mounted) {
        _forceScrollToLatest = true;
        setState(() {});
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          isGif
              ? 'Не удалось отправить GIF. Проверьте сеть и что в Supabase применена миграция типов сообщений: $e'
              : 'Не удалось отправить изображение: $e',
        ),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _pickAndSendDocument() async {
    final uid = _me();
    if (uid == null || _sending) return;
    setState(() => _sending = true);
    try {
      final res = await FilePicker.platform.pickFiles(
        withData: true,
        allowMultiple: false,
      );
      if (res == null || res.files.isEmpty) return;
      final f = res.files.single;
      final displayName = f.name.trim().isEmpty ? 'file' : f.name.trim();
      List<int>? bytes;
      if (f.bytes != null && f.bytes!.isNotEmpty) {
        bytes = f.bytes;
      } else if (f.path != null && f.path!.isNotEmpty) {
        bytes = await File(f.path!).readAsBytes();
      }
      if (bytes == null || bytes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Не удалось прочитать файл'),
            behavior: SnackBarBehavior.floating,
          ));
        }
        return;
      }
      final pathForMime = f.path ?? displayName;
      final mime = _mimeTypeForFilePath(pathForMime);
      final extFromName =
          displayName.contains('.') ? displayName.split('.').last : 'bin';
      final uploadPath =
          'dm/$uid/doc_${DateTime.now().millisecondsSinceEpoch}.$extFromName';
      await _client.storage.from(SupabaseConstants.bucketChatMedia).uploadBinary(
            uploadPath,
            Uint8List.fromList(bytes),
            fileOptions: FileOptions(contentType: mime, upsert: false),
          );
      final url = _client.storage
          .from(SupabaseConstants.bucketChatMedia)
          .getPublicUrl(uploadPath);
      await _client.from(SupabaseConstants.messagesTable).insert({
        'sender_id': uid,
        'receiver_id': widget.peerId,
        'text': '',
        'message_type': 'file',
        'file_url': url,
        'file_name': displayName,
      });
      if (mounted) _forceScrollToLatest = true;
    } catch (e) {
      if (!mounted) return;
      await _showSoftChatDialog(
        title: 'Файл не отправился',
        message: _userFacingChatStorageError(e),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showEventComposer() {
    final titleCtrl = TextEditingController();
    final placeCtrl = TextEditingController();
    var startsAt = DateTime.now().add(const Duration(hours: 1));
    startsAt = DateTime(
      startsAt.year,
      startsAt.month,
      startsAt.day,
      startsAt.hour,
      (startsAt.minute ~/ 15) * 15,
    );

    showDialog<void>(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (dialogContext, setDlg) => AlertDialog(
          title: const Text('Мероприятие'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Название',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Дата и время'),
                  subtitle: Text(
                    '${startsAt.day.toString().padLeft(2, '0')}.'
                    '${startsAt.month.toString().padLeft(2, '0')}.'
                    '${startsAt.year} '
                    '${startsAt.hour.toString().padLeft(2, '0')}:'
                    '${startsAt.minute.toString().padLeft(2, '0')}',
                  ),
                  trailing: const Icon(Icons.event_rounded),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: dialogContext,
                      initialDate: startsAt,
                      firstDate:
                          DateTime.now().subtract(const Duration(days: 1)),
                      lastDate:
                          DateTime.now().add(const Duration(days: 365 * 2)),
                    );
                    if (d == null || !dialogContext.mounted) return;
                    final t = await showTimePicker(
                      context: dialogContext,
                      initialTime: TimeOfDay(
                        hour: startsAt.hour,
                        minute: startsAt.minute,
                      ),
                    );
                    if (t == null || !dialogContext.mounted) return;
                    setDlg(() {
                      startsAt =
                          DateTime(d.year, d.month, d.day, t.hour, t.minute);
                    });
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: placeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Место (необязательно)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dlgCtx),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () async {
                final title = titleCtrl.text.trim();
                if (title.isEmpty) return;
                final uid = _me();
                if (uid == null) return;
                Navigator.pop(dlgCtx);
                final place = placeCtrl.text.trim();
                final payload = jsonEncode({
                  'title': title,
                  'starts_at': startsAt.toIso8601String(),
                  if (place.isNotEmpty) 'place': place,
                });
                try {
                  await _client.from(SupabaseConstants.messagesTable).insert({
                    'sender_id': uid,
                    'receiver_id': widget.peerId,
                    'text': payload,
                    'message_type': 'event',
                  });
                  if (mounted) {
                    _forceScrollToLatest = true;
                    setState(() {});
                  }
                } catch (e) {
                  if (!mounted || !context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Не удалось отправить мероприятие: $e'),
                    behavior: SnackBarBehavior.floating,
                  ));
                }
              },
              child: const Text('Отправить'),
            ),
          ],
        ),
      ),
    );
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

      // Reverse geocoding — получаем название места
      String address = '';
      try {
        final placemarks = await placemarkFromCoordinates(
          pos.latitude, pos.longitude,
        );
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          final parts = <String>[
            if (p.street != null && p.street!.isNotEmpty) p.street!,
            if (p.locality != null && p.locality!.isNotEmpty) p.locality!,
          ];
          address = parts.join(', ');
        }
      } catch (_) {}

      final payload = jsonEncode({
        'lat': pos.latitude,
        'lng': pos.longitude,
        if (address.isNotEmpty) 'label': address,
      });
      final tempId = 'tmp_loc_${DateTime.now().millisecondsSinceEpoch}';
      setState(() {
        _optimisticMessages.add({
          'id': tempId,
          'sender_id': uid,
          'receiver_id': widget.peerId,
          'text': payload,
          'created_at': DateTime.now().toIso8601String(),
          'message_type': 'location',
          '_pending': true,
        });
        _forceScrollToLatest = true;
      });
      Map<String, dynamic>? inserted;
      try {
        final raw = await _client
            .from(SupabaseConstants.messagesTable)
            .insert({
              'sender_id': uid,
              'receiver_id': widget.peerId,
              'text': payload,
              'message_type': 'location',
            })
            .select()
            .maybeSingle();
        if (raw != null) {
          inserted = Map<String, dynamic>.from(raw as Map);
        }
      } catch (e) {
        if (mounted) {
          setState(() =>
              _optimisticMessages.removeWhere((m) => m['id'] == tempId));
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Не удалось отправить геолокацию: $e'),
            behavior: SnackBarBehavior.floating,
          ));
        }
        return;
      }
      if (mounted && inserted != null) {
        setState(() {
          final idx = _optimisticMessages.indexWhere((m) => m['id'] == tempId);
          if (idx >= 0) {
            _optimisticMessages[idx] = Map<String, dynamic>.from(inserted!);
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

  ({double lat, double lng, String address})? _parseLocationMessage(
    String text,
    String messageType,
  ) {
    if (messageType == 'location') {
      try {
        final m = jsonDecode(text) as Map<String, dynamic>;
        final lat = (m['lat'] as num?)?.toDouble();
        final lng = (m['lng'] as num?)?.toDouble();
        if (lat == null || lng == null) return null;
        final label = (m['label'] as String?) ?? '';
        return (lat: lat, lng: lng, address: label);
      } catch (_) {
        return null;
      }
    }
    if (!text.startsWith('__location__|')) return null;
    final parts = text.split('|');
    if (parts.length < 3) return null;
    final lat = double.tryParse(parts[1]);
    final lng = double.tryParse(parts[2]);
    if (lat == null || lng == null) return null;
    final address = parts.length >= 4
        ? Uri.decodeComponent(parts.sublist(3).join('|'))
        : '';
    return (lat: lat, lng: lng, address: address);
  }

  ({String title, DateTime? when, String place})? _parseEventPayload(
    String text,
    String messageType,
  ) {
    if (messageType != 'event') return null;
    try {
      final m = jsonDecode(text) as Map<String, dynamic>;
      final title = (m['title'] as String?)?.trim() ?? '';
      if (title.isEmpty) return null;
      final whenRaw = m['starts_at'];
      final when = whenRaw is String ? DateTime.tryParse(whenRaw) : null;
      final place = (m['place'] as String?)?.trim() ?? '';
      return (title: title, when: when, place: place);
    } catch (_) {
      return null;
    }
  }

  static String _mimeTypeForFilePath(String path) {
    final l = path.toLowerCase();
    if (l.endsWith('.pdf')) return 'application/pdf';
    if (l.endsWith('.doc')) return 'application/msword';
    if (l.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (l.endsWith('.xls')) return 'application/vnd.ms-excel';
    if (l.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (l.endsWith('.ppt')) return 'application/vnd.ms-powerpoint';
    if (l.endsWith('.pptx')) {
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    }
    if (l.endsWith('.txt')) return 'text/plain';
    if (l.endsWith('.zip')) return 'application/zip';
    if (l.endsWith('.rar')) return 'application/x-rar-compressed';
    if (l.endsWith('.json')) return 'application/json';
    return 'application/octet-stream';
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
    // Удержание пальцем (как в мессенджерах), без задержки long-press.
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => onHoldStart(),
      onPointerUp: (_) => onHoldEnd(),
      onPointerCancel: (_) => onHoldCancel(),
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
// Видеокружок: удержание ~220 ms → запись (как голосовое рядом)
// ══════════════════════════════════════════════════════════════

class _VideoCircleHoldButton extends StatelessWidget {
  const _VideoCircleHoldButton({
    required this.onHoldArm,
    required this.onHoldDisarm,
  });

  final VoidCallback onHoldArm;
  final VoidCallback onHoldDisarm;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Удерживайте для видеокружка',
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => onHoldArm(),
        onPointerUp: (_) => onHoldDisarm(),
        onPointerCancel: (_) => onHoldDisarm(),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(
            Icons.videocam_rounded,
            size: 24,
            color: cs.primary,
          ),
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
    required this.onVoice,
    required this.onRoundVideo,
    required this.onLocation,
    required this.onContact,
    required this.onDocument,
    required this.onPoll,
    required this.onEvent,
  });

  final VoidCallback onPhoto;
  final VoidCallback onCamera;
  final VoidCallback onVoice;
  final VoidCallback onRoundVideo;
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
      _AttachItem(Icons.mic_rounded, 'Голосовое', const Color(0xFF6366F1), onVoice),
      _AttachItem(Icons.videocam_rounded, 'Видео\nкружок', const Color(0xFFF97316), onRoundVideo),
      _AttachItem(Icons.location_on_rounded, 'Местополо-жение', const Color(0xFF10B981), onLocation),
      _AttachItem(Icons.person_rounded, 'Контакт', const Color(0xFF3B82F6), onContact),
      _AttachItem(Icons.insert_drive_file_rounded, 'Документ', const Color(0xFFF59E0B), onDocument),
      _AttachItem(Icons.bar_chart_rounded, 'Опрос', const Color(0xFF06B6D4), onPoll),
      _AttachItem(Icons.event_rounded, 'Мероприятие', const Color(0xFFEF4444), onEvent),
    ];
    final cs = Theme.of(context).colorScheme;
    final surface = Theme.of(context).brightness == Brightness.dark
        ? cs.surfaceContainerHigh
        : cs.surface;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 24,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: cs.outline.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Вложение',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                ),
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 18,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.82,
                  children: items.map((item) {
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: item.onTap,
                        borderRadius: BorderRadius.circular(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 58,
                              height: 58,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    item.color.withValues(alpha: 0.22),
                                    item.color.withValues(alpha: 0.08),
                                  ],
                                ),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: item.color.withValues(alpha: 0.2),
                                ),
                              ),
                              child: Icon(item.icon,
                                  color: item.color, size: 28),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              item.label,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    height: 1.15,
                                    color: cs.onSurface.withValues(alpha: 0.88),
                                  ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
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
                _GifCatalogTab(onGifSelected: widget.onGifSelected),

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
// _GifCatalogTab — каталог GIF как в Telegram
// ══════════════════════════════════════════════════════════════

class _GifCatalogTab extends StatefulWidget {
  const _GifCatalogTab({required this.onGifSelected});
  final ValueChanged<String> onGifSelected;

  @override
  State<_GifCatalogTab> createState() => _GifCatalogTabState();
}

class _GifCatalogTabState extends State<_GifCatalogTab> {
  final _searchController = TextEditingController();
  String _query = '';
  int _categoryIndex = 0;

  static const _categories = [
    'Реакции', 'Привет', 'Смех', 'Любовь', 'Грусть', 'Огонь',
  ];

  static const _catalog = <String, List<Map<String, String>>>{
    'Реакции': [
      {'url': 'https://media.giphy.com/media/3oz8xLd9DJq2l2VFtu/giphy.gif', 'label': 'Танец'},
      {'url': 'https://media.giphy.com/media/xUA7bdpLxQhsSQkFug/giphy.gif', 'label': 'Да!'},
      {'url': 'https://media.giphy.com/media/3og0IFOzC2UFCVThUQ/giphy.gif', 'label': 'Нет'},
      {'url': 'https://media.giphy.com/media/l0MYt5jPR6QX5pnqM/giphy.gif', 'label': 'ОМГ'},
      {'url': 'https://media.giphy.com/media/26BRrSl9M5N8D5ygM/giphy.gif', 'label': 'Хм'},
      {'url': 'https://media.giphy.com/media/3ofT5sMBZImpHzH1FO/giphy.gif', 'label': 'Ура'},
    ],
    'Привет': [
      {'url': 'https://media.giphy.com/media/xT9IgG50Lg7rusyxxB/giphy.gif', 'label': 'Привет'},
      {'url': 'https://media.giphy.com/media/ASd0Ukj0y3qMM/giphy.gif', 'label': 'Пока'},
      {'url': 'https://media.giphy.com/media/IThjAlJnD9WNO/giphy.gif', 'label': 'Вау'},
      {'url': 'https://media.giphy.com/media/l0MYGb1LuZ3n7dRnO/giphy.gif', 'label': 'Йоу'},
    ],
    'Смех': [
      {'url': 'https://media.giphy.com/media/GRkmel8wEIoTe/giphy.gif', 'label': 'Смех'},
      {'url': 'https://media.giphy.com/media/5C0a8IItAWRebylDRX/giphy.gif', 'label': 'Ха-ха'},
      {'url': 'https://media.giphy.com/media/l3diU7InEOZLELEco/giphy.gif', 'label': 'LOL'},
      {'url': 'https://media.giphy.com/media/ZqlvCTNHpqrio/giphy.gif', 'label': 'Кека'},
    ],
    'Любовь': [
      {'url': 'https://media.giphy.com/media/26BRrSl9M5N8D5ygM/giphy.gif', 'label': 'Сердце'},
      {'url': 'https://media.giphy.com/media/l0MYGb1LuZ3n7dRnO/giphy.gif', 'label': 'Обнимашки'},
      {'url': 'https://media.giphy.com/media/26BRv0ThflsHhWp9O/giphy.gif', 'label': 'Люблю'},
      {'url': 'https://media.giphy.com/media/3oz8xAFtqoOUUrsh7W/giphy.gif', 'label': 'Kiss'},
    ],
    'Грусть': [
      {'url': 'https://media.giphy.com/media/3d3woRW2bSbDjBy2HD/giphy.gif', 'label': 'Плач'},
      {'url': 'https://media.giphy.com/media/OPU6wzx8JrHna/giphy.gif', 'label': 'Ой'},
      {'url': 'https://media.giphy.com/media/2vA33ikUb0Qz6/giphy.gif', 'label': 'Грустно'},
    ],
    'Огонь': [
      {'url': 'https://media.giphy.com/media/l1J9FEYgASQxjRLLO/giphy.gif', 'label': 'Огонь'},
      {'url': 'https://media.giphy.com/media/xUA7bdwsRuAstb8L7q/giphy.gif', 'label': 'Взрыв'},
      {'url': 'https://media.giphy.com/media/3oriNZoNvn73MZaFYk/giphy.gif', 'label': 'Топ'},
      {'url': 'https://media.giphy.com/media/26ufdipQqU2lhNA4g/giphy.gif', 'label': 'Круто'},
    ],
  };

  List<Map<String, String>> get _currentGifs {
    final cat = _categories[_categoryIndex];
    final all = _catalog[cat] ?? [];
    if (_query.isEmpty) return all;
    final q = _query.toLowerCase();
    return all.where((g) => (g['label'] ?? '').toLowerCase().contains(q)).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gifs = _currentGifs;
    return Column(
      children: [
        // Поиск
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
          child: TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _query = v),
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Поиск GIF...',
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey.shade400),
              filled: true,
              fillColor: Colors.grey.shade100,
              contentPadding: const EdgeInsets.symmetric(vertical: 6),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        // Категории
        SizedBox(
          height: 36,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: _categories.length,
            itemBuilder: (_, i) {
              final selected = i == _categoryIndex;
              return GestureDetector(
                onTap: () => setState(() => _categoryIndex = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: selected
                        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey.shade300,
                    ),
                  ),
                  child: Text(
                    _categories[i],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey.shade600,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        // GIF сетка
        Expanded(
          child: gifs.isEmpty
              ? Center(
                  child: Text(
                    'Ничего не найдено',
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                    childAspectRatio: 1,
                  ),
                  itemCount: gifs.length,
                  itemBuilder: (_, i) {
                    final gif = gifs[i];
                    final url = gif['url']!;
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => widget.onGifSelected(url),
                        borderRadius: BorderRadius.circular(8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl: url,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              color: Colors.grey.shade100,
                              child: const Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: Colors.grey.shade200,
                              child: Icon(Icons.gif_box_outlined,
                                  color: Colors.grey.shade400),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
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

// ══════════════════════════════════════════════════════════════
// _GifMessageBubble — анимиро��анный GIF
// ══════════════════════════════════════════════════════════════

class _FileMessageBubble extends StatelessWidget {
  const _FileMessageBubble({
    super.key,
    required this.fileUrl,
    required this.fileName,
    required this.isMe,
  });

  final String fileUrl;
  final String fileName;
  final bool isMe;

  Future<void> _open() async {
    final u = Uri.tryParse(fileUrl);
    if (u == null) return;
    if (await canLaunchUrl(u)) {
      await launchUrl(u, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = fileName.trim().isEmpty ? 'Файл' : fileName.trim();
    final fg = isMe ? Colors.white : Colors.black87;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _open,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.insert_drive_file_rounded, color: fg, size: 26),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  name,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventMessageBubble extends StatelessWidget {
  const _EventMessageBubble({
    super.key,
    required this.title,
    required this.when,
    required this.place,
    required this.isMe,
  });

  final String title;
  final DateTime? when;
  final String place;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final fg = isMe ? Colors.white : Colors.black87;
    final sub = isMe ? Colors.white70 : Colors.black54;
    var whenStr = '—';
    final w = when;
    if (w != null) {
      whenStr =
          '${w.day.toString().padLeft(2, '0')}.${w.month.toString().padLeft(2, '0')}.${w.year} '
          '${w.hour.toString().padLeft(2, '0')}:${w.minute.toString().padLeft(2, '0')}';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.event_available_rounded, size: 22, color: fg),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: fg,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(whenStr, style: TextStyle(color: sub, fontSize: 13)),
        if (place.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(place, style: TextStyle(color: sub, fontSize: 13)),
        ],
      ],
    );
  }
}

class _GifMessageBubble extends StatelessWidget {
  const _GifMessageBubble({
    super.key,
    required this.gifUrl,
    required this.isMe,
  });

  final String gifUrl;
  final bool isMe;

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
        alignment: Alignment.bottomLeft,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(
                maxWidth: 200, maxHeight: 200, minWidth: 100),
            // Image.network animate GIFs natively on mobile
            child: Image.network(
              gifUrl,
              fit: BoxFit.cover,
              width: 200,
              loadingBuilder: (ctx, child, progress) {
                if (progress == null) return child;
                return Container(
                  width: 200,
                  height: 140,
                  color: Colors.grey.shade200,
                  child: const Center(child: CircularProgressIndicator()),
                );
              },
              errorBuilder: (ctx, err, st) => Container(
                width: 200,
                height: 100,
                color: Colors.grey.shade200,
                child: const Icon(Icons.gif_box_rounded,
                    color: Colors.grey, size: 40),
              ),
            ),
          ),
          Positioned(
            bottom: 6,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'GIF',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// _LocationBubble — карта с OSM тайлами (WhatsApp-стиль)
// ══════════════════════════════════════════════════════════════

class _LocationBubble extends StatelessWidget {
  const _LocationBubble({
    super.key,
    required this.lat,
    required this.lng,
    required this.isMe,
    this.address = '',
  });

  final double lat;
  final double lng;
  final bool isMe;
  final String address;

  static const int _zoom = 15;
  static const double _tileSize = 256.0;
  static const double _bubbleW = 230.0;
  static const double _mapH = 130.0;

  // OSM tile coords
  static int _tx(double lon, int z) =>
      ((lon + 180.0) / 360.0 * (1 << z)).floor();

  static int _ty(double lat, int z) {
    final r = lat * math.pi / 180.0;
    return ((1.0 -
                math.log(math.tan(r) + 1.0 / math.cos(r)) / math.pi) /
            2.0 *
            (1 << z))
        .floor();
  }

  // Fractional offset of point inside its tile (0..256 px)
  static double _ox(double lon, int z) =>
      ((lon + 180.0) / 360.0 * (1 << z) - _tx(lon, z)) * _tileSize;

  static double _oy(double lat, int z) {
    final r = lat * math.pi / 180.0;
    final n = (1.0 -
            math.log(math.tan(r) + 1.0 / math.cos(r)) / math.pi) /
        2.0 *
        (1 << z);
    return (n - n.floor()) * _tileSize;
  }

  Future<void> _openMaps() async {
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final cx = _tx(lng, _zoom);
    final cy = _ty(lat, _zoom);
    // Pixel position of the pin within the 3x3 tile grid (each tile = 256px)
    final pinX = _tileSize + _ox(lng, _zoom);
    final pinY = _tileSize + _oy(lat, _zoom);
    // Scale factor to fit the 3x3 grid (768px wide) into _bubbleW
    final scale = _bubbleW / (_tileSize * 3);
    final scaledPinX = pinX * scale;
    final scaledPinY = pinY * scale;

    return GestureDetector(
      onTap: _openMaps,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: _bubbleW,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Map preview ──
              SizedBox(
                width: _bubbleW,
                height: _mapH,
                child: Stack(
                  children: [
                    // OSM тайлы 3×3
                    SizedBox(
                      width: _bubbleW,
                      height: _mapH,
                      child: ClipRect(
                        child: Transform.scale(
                          scale: scale,
                          alignment: Alignment.topLeft,
                          child: SizedBox(
                            width: _tileSize * 3,
                            height: _tileSize * 3,
                            child: GridView.builder(
                              physics: const NeverScrollableScrollPhysics(),
                              padding: EdgeInsets.zero,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                childAspectRatio: 1,
                              ),
                              itemCount: 9,
                              itemBuilder: (ctx, i) {
                                final row = i ~/ 3;
                                final col = i % 3;
                                final tx = cx - 1 + col;
                                final ty = cy - 1 + row;
                                final tileUrl =
                                    'https://tile.openstreetmap.org/$_zoom/$tx/$ty.png';
                                return CachedNetworkImage(
                                  imageUrl: tileUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (ctx, url) => Container(
                                      color: const Color(0xFFE8E0D8)),
                                  errorWidget: (ctx, url, err) => Container(
                                      color: const Color(0xFFE8E0D8)),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Пин геолокации
                    Positioned(
                      left: scaledPinX - 14,
                      top: scaledPinY - 28,
                      child: Icon(
                        Icons.location_on,
                        color: const Color(0xFFE53935),
                        size: 28,
                        shadows: const [
                          Shadow(
                            color: Colors.black38,
                            offset: Offset(0, 2),
                            blurRadius: 4,
                          )
                        ],
                      ),
                    ),
                    // Полупрозрачная кнопка "открыть"
                    Positioned(
                      top: 6,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 4,
                            )
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.open_in_new, size: 12,
                                color: Color(0xFF1565C0)),
                            SizedBox(width: 3),
                            Text(
                              'Открыть',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1565C0),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // ── Address footer ──
              Container(
                width: _bubbleW,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isMe
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey.shade200,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.location_on_rounded,
                      size: 16,
                      color: isMe
                          ? Colors.white70
                          : Colors.red.shade400,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        address.isNotEmpty ? address : 'Местоположение',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isMe ? Colors.white : Colors.black87,
                        ),
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
