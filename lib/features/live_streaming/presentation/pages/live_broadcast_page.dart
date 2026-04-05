import 'dart:async';
import 'dart:io';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/router/go_router_pop_safe.dart';
import '../../../../core/config/agora_live_config.dart';
import '../../../../core/permissions/agora_media_permissions.dart';
import '../../data/agora_join_token.dart';
import '../../../../core/utils/agora_uid.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/live_room_entity.dart';
import '../../domain/repositories/live_streaming_repository.dart';

/// Ведущий эфира: камера + Agora Live Broadcasting.
class LiveBroadcastPage extends StatefulWidget {
  const LiveBroadcastPage({super.key});

  @override
  State<LiveBroadcastPage> createState() => _LiveBroadcastPageState();
}

class _LiveBroadcastPageState extends State<LiveBroadcastPage>
    with SingleTickerProviderStateMixin {
  final _titleCtrl = TextEditingController();

  LiveRoomEntity? _room;
  RtcEngine? _engine;
  bool _joining = false;
  bool _joined = false;
  String? _error;
  late final RtcEngineEventHandler _handler;

  late final AnimationController _pregameIntro;
  late final Animation<double> _pregameFade;
  late final Animation<Offset> _pregameSlide;

  bool get _inStream => _room != null && _joined;

  static const Color _liveAccent = Color(0xFFFF3355);
  static const Color _fieldFill = Color(0xFF2A2A30);

  @override
  void initState() {
    super.initState();
    _pregameIntro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
    _pregameFade = CurvedAnimation(
      parent: _pregameIntro,
      curve: const Interval(0, 0.85, curve: Curves.easeOutCubic),
    );
    _pregameSlide = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _pregameIntro,
      curve: Curves.easeOutCubic,
    ));
    unawaited(_pregameIntro.forward());

    _handler = RtcEngineEventHandler(
      onError: (err, msg) {
        if (!mounted) return;
        setState(() => _error = 'Agora: $msg ($err)');
      },
      onJoinChannelSuccess: (_, __) {
        if (mounted) setState(() => _joined = true);
      },
      onLeaveChannel: (_, __) {
        if (mounted) setState(() => _joined = false);
      },
    );
  }

  @override
  void dispose() {
    _pregameIntro.dispose();
    _titleCtrl.dispose();
    unawaited(_disposeEngine());
    super.dispose();
  }

  Future<void> _disposeEngine() async {
    final e = _engine;
    _engine = null;
    if (e == null) return;
    try {
      e.unregisterEventHandler(_handler);
      await e.leaveChannel();
      await e.release();
    } catch (_) {}
  }

  Future<void> _endRoomInDb(String? roomId) async {
    if (roomId == null || !mounted) return;
    try {
      await context.read<LiveStreamingRepository>().endLiveRoom(roomId);
    } catch (_) {}
  }

  Future<void> _shutdownFully() async {
    final id = _room?.id;
    await _disposeEngine();
    await _endRoomInDb(id);
    if (mounted) {
      setState(() {
        _room = null;
        _joined = false;
        _joining = false;
      });
    }
  }

  Future<void> _start() async {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Войдите, чтобы вести эфир')),
      );
      return;
    }
    if (!AgoraLiveConfig.isConfigured) {
      setState(() => _error = 'Нет AGORA_APP_ID в .env — см. AgoraLiveConfig');
      return;
    }

    final repo = context.read<LiveStreamingRepository>();

    if (!await ensureAgoraCameraAndMicrophone(context)) {
      if (mounted) {
        setState(() => _error = 'Нужны разрешения камеры и микрофона');
      }
      return;
    }

    setState(() {
      _joining = true;
      _error = null;
    });

    // Сначала убираем фокус с поля — иначе на части устройств последний ввод
    // не попадает в TextEditingController до нажатия кнопки.
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;

    final trimmedTitle = _titleCtrl.text.trim();
    final titleForRoom =
        trimmedTitle.isEmpty ? 'Прямой эфир' : trimmedTitle;

    LiveRoomEntity? created;

    try {
      created = await repo.createLiveRoom(title: titleForRoom);

      final engine = createAgoraRtcEngine();
      await engine.initialize(
        RtcEngineContext(appId: AgoraLiveConfig.appId),
      );
      engine.registerEventHandler(_handler);
      await engine.enableVideo();
      await engine.startPreview();

      final uid = agoraUidFromUserId(auth.user.id);
      final rtcToken = await resolveAgoraJoinToken(
        Supabase.instance.client,
        channelName: created.agoraChannelId,
        uid: uid,
        publisher: true,
      );
      await engine.joinChannel(
        token: rtcToken,
        channelId: created.agoraChannelId,
        uid: uid,
        options: const ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
        ),
      );

      if (!mounted) {
        engine.unregisterEventHandler(_handler);
        await engine.leaveChannel();
        await engine.release();
        await repo.endLiveRoom(created.id);
        return;
      }

      setState(() {
        _room = created;
        _engine = engine;
        _joining = false;
      });
    } catch (e) {
      await _disposeEngine();
      if (created != null) {
        await repo.endLiveRoom(created.id);
      }
      if (mounted) {
        setState(() {
          _joining = false;
          _room = null;
          _error = e.toString();
        });
      }
    }
  }

  Future<bool> _confirmEnd() async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Завершить эфир?'),
        content: const Text('Трансляция остановится для всех зрителей.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Завершить'),
          ),
        ],
      ),
    );
    return r == true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_inStream && !_joining,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (!_inStream) {
          if (context.mounted) context.popOrGoHomeFeed();
          return;
        }
        if (await _confirmEnd()) {
          await _shutdownFully();
          if (context.mounted) context.popOrGoHomeFeed();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: _room == null,
        appBar: AppBar(
          backgroundColor: _room == null
              ? Colors.transparent
              : Colors.black.withValues(alpha: 0.35),
          elevation: 0,
          scrolledUnderElevation: 0,
          foregroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.white),
          titleTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          title: const Text('Прямой эфир'),
          actions: [
            if (_inStream)
              TextButton(
                onPressed: () async {
                  if (await _confirmEnd()) {
                    await _shutdownFully();
                    if (context.mounted) context.popOrGoHomeFeed();
                  }
                },
                child: const Text(
                  'Стоп',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
          ],
        ),
        body: _room == null
            ? _buildPregame(context)
            : _buildLive(context),
      ),
    );
  }

  Widget _buildPregame(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight + 8;

    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF0D0D12),
                Color(0xFF1A1422),
                Color(0xFF08080C),
              ],
            ),
          ),
        ),
        Positioned(
          right: -60,
          top: 80,
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _pregameIntro,
              builder: (context, child) {
                return Opacity(
                  opacity: 0.12 * _pregameFade.value,
                  child: child,
                );
              },
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _liveAccent.withValues(alpha: 0.5),
                  boxShadow: [
                    BoxShadow(
                      color: _liveAccent.withValues(alpha: 0.35),
                      blurRadius: 80,
                      spreadRadius: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        FadeTransition(
          opacity: _pregameFade,
          child: SlideTransition(
            position: _pregameSlide,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(24, topInset, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: _liveAccent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _liveAccent.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _LivePulseDot(color: _liveAccent),
                            const SizedBox(width: 8),
                            Text(
                              'LIVE',
                              style: TextStyle(
                                color: _liveAccent.withValues(alpha: 0.95),
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Новый эфир',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Зрители увидят название в списке эфиров. Можно оставить пустым.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.62),
                      height: 1.4,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 28),
                  if (!AgoraLiveConfig.isConfigured) ...[
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2D2418),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFFFFB74D).withValues(alpha: 0.35),
                        ),
                      ),
                      child: const Text(
                        'Видеоэфир идёт через сервис Agora (бесплатный лимит для разработки).\n\n'
                        'Что сделать один раз:\n'
                        '• Зайдите на console.agora.io → создайте проект → скопируйте App ID.\n'
                        '• Вставьте в файл .env строку: AGORA_APP_ID=ваш_ключ\n'
                        '• Перезапустите приложение.\n\n'
                        'Если в Agora включён «App Certificate»: задеплойте функцию '
                        'agora-rtc-token и добавьте в Supabase Secrets сертификат проекта, '
                        'либо временно отключите сертификат в консоли Agora для теста.',
                        style: TextStyle(
                          color: Color(0xFFFFE8CC),
                          height: 1.45,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  TextField(
                    controller: _titleCtrl,
                    style: const TextStyle(
                      color: Color(0xFFF5F5F7),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    cursorColor: _liveAccent,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: _fieldFill,
                      labelText: 'Название эфира',
                      hintText: 'Например: Разбор новостей',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                      labelStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                      ),
                      floatingLabelStyle: TextStyle(
                        color: _liveAccent.withValues(alpha: 0.9),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.14),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: _liveAccent,
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 18,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: _joining ? null : _start,
                    style: FilledButton.styleFrom(
                      backgroundColor: _liveAccent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          _liveAccent.withValues(alpha: 0.35),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: _joining ? 0 : 2,
                      shadowColor: _liveAccent.withValues(alpha: 0.45),
                    ),
                    icon: _joining
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.videocam_rounded, size: 22),
                    label: Text(
                      _joining ? 'Подключение…' : 'Начать эфир',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 18),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      switchInCurve: Curves.easeOut,
                      child: Container(
                        key: ValueKey(_error),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.red.shade900.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.redAccent.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              color: Colors.red.shade200,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: Colors.red.shade100,
                                  fontSize: 13,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLive(BuildContext context) {
    final engine = _engine;
    if (engine == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        AgoraVideoView(
          controller: VideoViewController(
            rtcEngine: engine,
            canvas: const VideoCanvas(uid: 0),
            useFlutterTexture: Platform.isIOS,
            useAndroidSurfaceView: Platform.isAndroid,
          ),
          onAgoraVideoViewCreated: (_) {
            engine.startPreview();
          },
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 32,
          child: Text(
            _room!.title.isEmpty ? 'В эфире' : _room!.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              shadows: [Shadow(blurRadius: 8, color: Colors.black)],
            ),
          ),
        ),
      ],
    );
  }
}

class _LivePulseDot extends StatefulWidget {
  const _LivePulseDot({required this.color});

  final Color color;

  @override
  State<_LivePulseDot> createState() => _LivePulseDotState();
}

class _LivePulseDotState extends State<_LivePulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_pulse.value);
        final scale = 0.88 + 0.12 * t;
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.55),
                  blurRadius: 3 + 5 * t,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
