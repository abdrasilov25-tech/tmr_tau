import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../live/live_screen.dart';
import '../../../live_streaming/domain/entities/live_room_entity.dart';
import '../../../live_streaming/domain/repositories/live_streaming_repository.dart';

/// Хаб: список эфиров (как лента TikTok Live) + вход вещателя и LIVE Battle.
class LiveStreamPage extends StatelessWidget {
  const LiveStreamPage({super.key});

  @override
  Widget build(BuildContext context) {
    final me = Supabase.instance.client.auth.currentUser?.id;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('Прямой эфир'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      final auth = context.read<AuthBloc>().state;
                      if (auth is! AuthAuthenticated) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Войдите, чтобы вести эфир'),
                          ),
                        );
                        return;
                      }
                      context.push('/live/host');
                    },
                    icon: const Icon(Icons.videocam_rounded),
                    label: const Text('Начать эфир'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.push('/live-battle-lobby'),
                    icon: const Icon(Icons.sports_kabaddi_rounded),
                    label: const Text('Баттл'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const LiveScreen(channelId: 'test_channel'),
                ),
              );
            },
            icon: Icon(
              Icons.science_outlined,
              color: Colors.white.withValues(alpha: 0.5),
              size: 18,
            ),
            label: Text(
              'Тест Agora (test_channel)',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Сейчас в эфире',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: StreamBuilder<List<LiveRoomEntity>>(
              stream: context.read<LiveStreamingRepository>().watchActiveLiveRooms(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Не удалось загрузить эфиры.\n'
                        'Проверьте миграцию live_rooms и Realtime в Supabase.\n'
                        '${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white54, height: 1.35),
                      ),
                    ),
                  );
                }
                final list = snapshot.data ?? const <LiveRoomEntity>[];
                if (list.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Пока никто не в эфире.\n'
                        'Нажмите «Начать эфир» или попросите друга запустить трансляцию.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          height: 1.4,
                        ),
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final r = list[i];
                    final isMine = me != null && r.hostId == me;
                    return Material(
                      color: const Color(0xFF1A1A24),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: isMine
                            ? null
                            : () => context.push('/live/watch/${r.id}'),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.85),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.fiber_manual_record,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      r.title.isEmpty ? 'Эфир' : r.title,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      isMine
                                          ? 'Это ваш эфир (откройте экран вещателя)'
                                          : 'Нажмите, чтобы смотреть',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.45),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (!isMine)
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  color: Colors.white54,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
