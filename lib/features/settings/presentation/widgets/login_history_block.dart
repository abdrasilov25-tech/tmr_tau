import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/widgets/app_error_view.dart';
import '../../../../core/widgets/app_loading.dart';
import '../../data/repositories/settings_repository_impl.dart';
import '../../domain/entities/login_history_entity.dart';

/// История входов: один запрос при монтировании, не в [build] родителя.
class LoginHistoryBlock extends StatefulWidget {
  const LoginHistoryBlock({
    super.key,
    required this.userId,
  });

  final String userId;

  @override
  State<LoginHistoryBlock> createState() => _LoginHistoryBlockState();
}

class _LoginHistoryBlockState extends State<LoginHistoryBlock> {
  late Future<List<LoginHistoryEntity>> _future;

  Future<List<LoginHistoryEntity>> _load() {
    final repo = SettingsRepositoryImpl(Supabase.instance.client);
    return repo.getMyLoginHistory(
      userId: widget.userId,
      limit: 10,
    );
  }

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  void _retry() {
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<LoginHistoryEntity>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: AppLoading());
        }
        if (snapshot.hasError) {
          return AppErrorView(
            message: snapshot.error.toString(),
            onRetry: _retry,
          );
        }
        final items = snapshot.data ?? const <LoginHistoryEntity>[];
        if (items.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Пока нет сохраненных данных о входах.',
            ),
          );
        }
        return Column(
          children: items
              .map((e) => _LoginHistoryRow(
                    loggedInAt: e.loggedInAt,
                    ipAddress: e.ipAddress,
                  ))
              .toList(growable: false),
        );
      },
    );
  }
}

class _LoginHistoryRow extends StatelessWidget {
  const _LoginHistoryRow({
    required this.loggedInAt,
    this.ipAddress,
  });

  final DateTime loggedInAt;
  final String? ipAddress;

  @override
  Widget build(BuildContext context) {
    final dt =
        '${loggedInAt.day.toString().padLeft(2, '0')}.${loggedInAt.month.toString().padLeft(2, '0')}.${loggedInAt.year}';
    final hasIp = ipAddress != null && ipAddress!.isNotEmpty;
    final ip = hasIp ? ' • ${ipAddress!}' : '';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text('Вход: $dt'),
      subtitle: ip.isEmpty ? null : Text(ip),
    );
  }
}
