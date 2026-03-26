import 'package:flutter/material.dart';

import '../../../../core/widgets/cached_avatar.dart';
import '../../data/invite_candidates.dart';

/// Мультивыбор людей для приглашения в канал (как в Telegram).
Future<List<String>?> showChannelInviteUserPicker(
  BuildContext context, {
  required List<InviteCandidate> candidates,
  Set<String> initialSelection = const {},
  String title = 'Пригласить в канал',
  String confirmLabel = 'Пригласить выбранных',
  String emptyHint = 'Некого пригласить — подпишитесь на людей или получите подписчиков.',
}) async {
  if (candidates.isEmpty) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(emptyHint)),
    );
    return null;
  }

  final selected = <String>{...initialSelection};
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      final h = MediaQuery.sizeOf(ctx).height * 0.55;
      return StatefulBuilder(
        builder: (ctx, setSheet) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Только люди из ваших подписок и подписчиков.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: h,
                    child: ListView.builder(
                      itemCount: candidates.length,
                      itemBuilder: (_, i) {
                        final u = candidates[i];
                        final isOn = selected.contains(u.id);
                        return CheckboxListTile(
                          value: isOn,
                          onChanged: (v) {
                            setSheet(() {
                              if (v == true) {
                                selected.add(u.id);
                              } else {
                                selected.remove(u.id);
                              }
                            });
                          },
                          secondary: CachedAvatar(
                            imageUrl: u.avatarUrl,
                            radius: 18,
                            fallbackText: u.name,
                          ),
                          title: Text(u.name),
                          controlAffinity: ListTileControlAffinity.trailing,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: selected.isEmpty
                          ? null
                          : () => Navigator.pop(ctx, true),
                      child: Text(confirmLabel),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
  if (ok != true || selected.isEmpty) return null;
  return selected.toList(growable: false);
}
