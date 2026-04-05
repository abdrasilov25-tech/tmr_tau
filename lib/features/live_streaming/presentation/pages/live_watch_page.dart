import 'dart:async';
import 'dart:io';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/router/go_router_pop_safe.dart';
import '../../../../core/config/agora_live_config.dart';
import '../../../../core/utils/agora_uid.dart';
import '../../data/agora_join_token.dart';
import '../../domain/entities/live_room_entity.dart';
import '../../domain/repositories/live_streaming_repository.dart';

/// Зритель: приём видео ведущего (Agora audience).
class LiveWatchPage extends StatefulWidget {
  const LiveWatchPage({super.key, required this.roomId});

  final String roomId;

  @override
  State<LiveWatchPage> createState() => _LiveWatchPageState();
}

class _LiveWatchPageState extends State<LiveWatchPage> {
  LiveRoomEntity? _room;
  RtcEngine? _engine;
  bool _loading = true;
  String? _error;
  final Set<int> _remoteUids = {};
  late final RtcEngineEventHandler _handler;

  @override
  void initState() {
    super.initState();
    _handler = RtcEngineEventHandler(
      onError: (err, msg) {
        if (!mounted) return;
        setState(() => _error = 'Agora: $msg ($err)');
      },
      onUserJoined: (_, remoteUid, __) {
        if (mounted) setState(() => _remoteUids.add(remoteUid));
      },
      onUserOffline: (_, remoteUid, __) {
        if (mounted) setState(() => _remoteUids.remove(remoteUid));
      },
    );
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
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

  Future<void> _bootstrap() async {
    if (!mounted) return;
    final repo = context.read<LiveStreamingRepository>();

    if (!AgoraLiveConfig.isConfigured) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Нет AGORA_APP_ID в .env';
        });
      }
      return;
    }

    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Войдите, чтобы смотреть эфир';
        });
      }
      return;
    }

    try {
      final room = await repo.getLiveRoom(widget.roomId);
      if (!mounted) return;
      if (room == null || !room.isLive) {
        setState(() {
          _loading = false;
          _error = 'Эфир завершён или не найден';
        });
        return;
      }

      final engine = createAgoraRtcEngine();
      await engine.initialize(
        RtcEngineContext(appId: AgoraLiveConfig.appId),
      );
      engine.registerEventHandler(_handler);
      await engine.enableVideo();

      final agoraUid = agoraUidFromUserId(uid);
      final rtcToken = await resolveAgoraJoinToken(
        Supabase.instance.client,
        channelName: room.agoraChannelId,
        uid: agoraUid,
        publisher: false,
      );
      await engine.joinChannel(
        token: rtcToken,
        channelId: room.agoraChannelId,
        uid: agoraUid,
        options: const ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleAudience,
          channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
        ),
      );

      if (!mounted) {
        engine.unregisterEventHandler(_handler);
        await engine.leaveChannel();
        await engine.release();
        return;
      }

      setState(() {
        _room = room;
        _engine = engine;
        _loading = false;
      });
    } catch (e) {
      await _disposeEngine();
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(_room?.title.isNotEmpty == true ? _room!.title : 'Эфир'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.popOrGoHomeFeed(),
                child: const Text('Назад'),
              ),
            ],
          ),
        ),
      );
    }

    final engine = _engine;
    final room = _room;
    if (engine == null || room == null) {
      return const SizedBox.shrink();
    }

    final remoteList = _remoteUids.toList()..sort();
    final remoteUid = remoteList.isEmpty ? null : remoteList.first;

    return Column(
      children: [
        Expanded(
          child: remoteUid == null
              ? Center(
                  child: Text(
                    'Ожидаем ведущего…',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                )
              : AgoraVideoView(
                  controller: VideoViewController.remote(
                    rtcEngine: engine,
                    canvas: VideoCanvas(uid: remoteUid),
                    connection: RtcConnection(channelId: room.agoraChannelId),
                    useFlutterTexture: Platform.isIOS,
                    useAndroidSurfaceView: Platform.isAndroid,
                  ),
                ),
        ),
      ],
    );
  }
}
