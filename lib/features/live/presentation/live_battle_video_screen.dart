import 'dart:async';
import 'dart:io';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/agora_live_config.dart';
import '../../live_battle/domain/entities/gift.dart';
import '../../live_battle/domain/entities/live_battle.dart';
import '../../live_battle/domain/repositories/live_battle_repository.dart';

/// Видео-слой для LIVE battle: Agora-канал = [battleId], поверх — лайки/подарки/счёт (те же RPC).
class LiveBattleVideoScreen extends StatefulWidget {
  const LiveBattleVideoScreen({
    super.key,
    required this.battleId,
    required this.isHost,
  });

  final String battleId;
  final bool isHost;

  @override
  State<LiveBattleVideoScreen> createState() => _LiveBattleVideoScreenState();
}

class _LiveBattleVideoScreenState extends State<LiveBattleVideoScreen> {
  RtcEngine? _engine;
  late final RtcEngineEventHandler _handler;

  StreamSubscription<LiveBattle>? _battleSub;

  LiveBattle? _battle;
  List<Gift> _gifts = const [];
  final Set<int> _remoteUids = <int>{};

  bool _loadingBattle = true;
  bool _joiningChannel = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _handler = RtcEngineEventHandler(
      onError: (err, msg) {
        if (!mounted) return;
        setState(() => _error = '$msg ($err)');
      },
      onUserJoined: (_, remoteUid, __) {
        if (!mounted) return;
        setState(() => _remoteUids.add(remoteUid));
      },
      onUserOffline: (_, remoteUid, __) {
        if (!mounted) return;
        setState(() => _remoteUids.remove(remoteUid));
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_bootstrap());
    });
  }

  Future<void> _bootstrap() async {
    if (!mounted) return;
    final repo = context.read<LiveBattleRepository>();

    if (!AgoraLiveConfig.isConfigured) {
      setState(() {
        _loadingBattle = false;
        _joiningChannel = false;
        _error = 'Нет AGORA_APP_ID в .env';
      });
      return;
    }

    try {
      final battle = await repo.fetchBattle(widget.battleId);
      final gifts = await repo.getGifts();
      if (!mounted) return;
      if (battle == null) {
        setState(() {
          _loadingBattle = false;
          _joiningChannel = false;
          _error = 'Баттл не найден';
        });
        return;
      }
      setState(() {
        _battle = battle;
        _gifts = gifts;
        _loadingBattle = false;
      });

      _battleSub = repo.watchBattle(widget.battleId).listen((b) {
        if (mounted) setState(() => _battle = b);
      });

      await _initAgora();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingBattle = false;
          _joiningChannel = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _initAgora() async {
    try {
      final cam = await Permission.camera.request();
      final mic = await Permission.microphone.request();
      if (!cam.isGranted || !mic.isGranted) {
        if (mounted) {
          setState(() {
            _joiningChannel = false;
            _error = 'Нужны камера и микрофон';
          });
        }
        return;
      }

      final engine = createAgoraRtcEngine();
      await engine.initialize(
        RtcEngineContext(appId: AgoraLiveConfig.appId),
      );
      engine.registerEventHandler(_handler);
      await engine.enableVideo();

      if (widget.isHost) {
        await engine.startPreview();
      }

      await engine.joinChannel(
        token: AgoraLiveConfig.token,
        channelId: widget.battleId,
        uid: 0,
        options: ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
          clientRoleType: widget.isHost
              ? ClientRoleType.clientRoleBroadcaster
              : ClientRoleType.clientRoleAudience,
        ),
      );

      if (!mounted) {
        engine.unregisterEventHandler(_handler);
        await engine.leaveChannel();
        await engine.release();
        return;
      }
      setState(() {
        _engine = engine;
        _joiningChannel = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _joiningChannel = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _sendLike(String targetHost) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    final repo = context.read<LiveBattleRepository>();
    if (uid == null) return;
    try {
      await repo.sendLike(
        battleId: widget.battleId,
        userId: uid,
        targetHost: targetHost,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Лайк: $e')),
        );
      }
    }
  }

  Future<void> _sendGift(String giftId, String targetHost) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    final repo = context.read<LiveBattleRepository>();
    if (uid == null) return;
    try {
      await repo.sendGift(
        battleId: widget.battleId,
        giftId: giftId,
        senderId: uid,
        targetHost: targetHost,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Подарок: $e')),
        );
      }
    }
  }

  void _openGiftPicker(String targetHost) {
    if (_gifts.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: _gifts
                .map(
                  (g) => ListTile(
                    title: Text(
                      g.name,
                      style: const TextStyle(color: Colors.white),
                    ),
                    trailing: Text(
                      '${g.price}',
                      style: const TextStyle(color: Colors.amber),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      unawaited(_sendGift(g.id, targetHost));
                    },
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    unawaited(_battleSub?.cancel());
    unawaited(_disposeAgora());
    super.dispose();
  }

  Future<void> _disposeAgora() async {
    final e = _engine;
    _engine = null;
    if (e == null) return;
    try {
      e.unregisterEventHandler(_handler);
      await e.leaveChannel();
      await e.release();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingBattle || _joiningChannel) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('Видео баттл'),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    if (_error != null && _engine == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('Видео баттл'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ),
      );
    }

    final battle = _battle;
    final engine = _engine;
    final remoteList = _remoteUids.toList()..sort();
    final remoteUid = remoteList.isEmpty ? null : remoteList.first;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (engine != null)
            Column(
              children: [
                Expanded(
                  child: Container(
                    color: Colors.black,
                    child: remoteUid == null
                        ? Center(
                            child: Text(
                              widget.isHost
                                  ? 'Ожидаем второго участника…'
                                  : 'Ожидаем эфир…',
                              style: const TextStyle(color: Colors.white54),
                            ),
                          )
                        : AgoraVideoView(
                            controller: VideoViewController.remote(
                              rtcEngine: engine,
                              canvas: VideoCanvas(uid: remoteUid),
                              connection: RtcConnection(
                                channelId: widget.battleId,
                              ),
                              useFlutterTexture: Platform.isIOS,
                              useAndroidSurfaceView: Platform.isAndroid,
                            ),
                          ),
                  ),
                ),
                if (widget.isHost)
                  Expanded(
                    child: Container(
                      color: Colors.black,
                      child: AgoraVideoView(
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
                    ),
                  ),
              ],
            )
          else
            const SizedBox.shrink(),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                color: Colors.white,
              ),
            ),
          ),
          if (battle != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: MediaQuery.of(context).padding.bottom + 16,
              child: _BattleOverlay(
                battle: battle,
                onLikeA: () => unawaited(_sendLike(battle.hostA)),
                onLikeB: () => unawaited(_sendLike(battle.hostB)),
                onGiftA: () => _openGiftPicker(battle.hostA),
                onGiftB: () => _openGiftPicker(battle.hostB),
              ),
            ),
        ],
      ),
    );
  }
}

class _BattleOverlay extends StatelessWidget {
  const _BattleOverlay({
    required this.battle,
    required this.onLikeA,
    required this.onLikeB,
    required this.onGiftA,
    required this.onGiftB,
  });

  final LiveBattle battle;
  final VoidCallback onLikeA;
  final VoidCallback onLikeB;
  final VoidCallback onGiftA;
  final VoidCallback onGiftB;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            'A: ${battle.scoreA}  ·  B: ${battle.scoreB}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _OverlayAction(
              label: 'A',
              icon: Icons.favorite_rounded,
              color: const Color(0xFF60A5FA),
              onLike: onLikeA,
              onGift: onGiftA,
            ),
            _OverlayAction(
              label: 'B',
              icon: Icons.favorite_rounded,
              color: const Color(0xFFF87171),
              onLike: onLikeB,
              onGift: onGiftB,
            ),
          ],
        ),
      ],
    );
  }
}

class _OverlayAction extends StatelessWidget {
  const _OverlayAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onLike,
    required this.onGift,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onLike;
  final VoidCallback onGift;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          children: [
            IconButton(
              style: IconButton.styleFrom(backgroundColor: color),
              onPressed: onLike,
              icon: Icon(icon, color: Colors.white),
            ),
            Text('Лайк $label', style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ),
        const SizedBox(width: 12),
        Column(
          children: [
            IconButton(
              style: IconButton.styleFrom(
                backgroundColor: Colors.purple.shade700,
              ),
              onPressed: onGift,
              icon: const Icon(Icons.card_giftcard_rounded, color: Colors.white),
            ),
            Text('Подарок $label', style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ),
      ],
    );
  }
}
