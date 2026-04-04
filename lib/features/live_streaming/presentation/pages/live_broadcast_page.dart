import 'dart:async';
import 'dart:io';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/agora_live_config.dart';
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

class _LiveBroadcastPageState extends State<LiveBroadcastPage> {
  final _titleCtrl = TextEditingController();

  LiveRoomEntity? _room;
  RtcEngine? _engine;
  bool _joining = false;
  bool _joined = false;
  String? _error;
  late final RtcEngineEventHandler _handler;

  bool get _inStream => _room != null && _joined;

  @override
  void initState() {
    super.initState();
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

    final cam = await Permission.camera.request();
    final mic = await Permission.microphone.request();
    if (!cam.isGranted || !mic.isGranted) {
      setState(() => _error = 'Нужны разрешения камеры и микрофона');
      return;
    }

    setState(() {
      _joining = true;
      _error = null;
    });

    LiveRoomEntity? created;

    try {
      created = await repo.createLiveRoom(title: _titleCtrl.text);

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
          if (context.mounted) context.pop();
          return;
        }
        if (await _confirmEnd()) {
          await _shutdownFully();
          if (context.mounted) context.pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          title: const Text('Прямой эфир'),
          actions: [
            if (_inStream)
              TextButton(
                onPressed: () async {
                  if (await _confirmEnd()) {
                    await _shutdownFully();
                    if (context.mounted) context.pop();
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
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!AgoraLiveConfig.isConfigured) ...[
            Card(
              color: Colors.orange.shade900.withValues(alpha: 0.4),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Видеоэфир идёт через сервис Agora (бесплатный лимит для разработки).\n\n'
                  'Что сделать один раз:\n'
                  '• Зайдите на console.agora.io → создайте проект → скопируйте App ID.\n'
                  '• Вставьте в файл .env строку: AGORA_APP_ID=ваш_ключ\n'
                  '• Перезапустите приложение.\n\n'
                  'Если в Agora включён «App Certificate»: задеплойте функцию '
                  'agora-rtc-token и добавьте в Supabase Secrets сертификат проекта, '
                  'либо временно отключите сертификат в консоли Agora для теста.',
                  style: TextStyle(color: Colors.white, height: 1.45),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _titleCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Название эфира',
              labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
              ),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _joining ? null : _start,
            icon: _joining
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.videocam_rounded),
            label: Text(_joining ? 'Подключение…' : 'Начать эфир'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
            ),
          ],
        ],
      ),
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
