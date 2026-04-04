import 'dart:async';
import 'dart:io';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Простой полноэкранный локальный превью + вход в канал Agora.
///
/// App ID задан по ТЗ интеграции; для продакшена при необходимости вынесите в конфиг.
class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key, required this.channelId});

  final String channelId;

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  RtcEngine? _engine;
  bool _joining = true;
  String? _error;

  late final RtcEngineEventHandler _handler;

  /// App ID из задания на интеграцию Agora.
  static const String _appId = 'ca25294379a6406386da96a5d367cdc4';

  @override
  void initState() {
    super.initState();
    _handler = RtcEngineEventHandler(
      onError: (err, msg) {
        if (mounted) setState(() => _error = '$msg ($err)');
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_setup());
    });
  }

  Future<void> _setup() async {
    try {
      final cam = await Permission.camera.request();
      final mic = await Permission.microphone.request();
      if (!cam.isGranted || !mic.isGranted) {
        if (mounted) {
          setState(() {
            _joining = false;
            _error = 'Нужны разрешения камеры и микрофона';
          });
        }
        return;
      }

      final engine = createAgoraRtcEngine();
      await engine.initialize(
        RtcEngineContext(appId: _appId),
      );
      engine.registerEventHandler(_handler);
      await engine.enableVideo();
      await engine.startPreview();

      // SDK требует String; пустая строка — без RTC Token (без App Certificate в Agora).
      await engine.joinChannel(
        token: '',
        channelId: widget.channelId,
        uid: 0,
        options: const ChannelMediaOptions(),
      );

      if (!mounted) {
        await _releaseEngine(engine);
        return;
      }
      setState(() {
        _engine = engine;
        _joining = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _joining = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _releaseEngine(RtcEngine engine) async {
    try {
      engine.unregisterEventHandler(_handler);
      await engine.leaveChannel();
      await engine.release();
    } catch (_) {}
  }

  @override
  void dispose() {
    final e = _engine;
    _engine = null;
    if (e != null) {
      unawaited(_releaseEngine(e));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_engine != null && _error == null)
            AgoraVideoView(
              controller: VideoViewController(
                rtcEngine: _engine!,
                canvas: const VideoCanvas(uid: 0),
                useFlutterTexture: Platform.isIOS,
                useAndroidSurfaceView: Platform.isAndroid,
              ),
              onAgoraVideoViewCreated: (_) {
                _engine?.startPreview();
              },
            )
          else if (_joining)
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            )
          else
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error ?? 'Ошибка',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded),
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
