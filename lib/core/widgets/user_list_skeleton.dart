import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Плейсхолдер списка пользователей (подписки / подписчики).
class UserListSkeleton extends StatelessWidget {
  const UserListSkeleton({super.key, this.itemCount = 8});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final base = Colors.grey.shade700;
    final highlight = Colors.grey.shade500;
    return ListView.separated(
      itemCount: itemCount,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        return Shimmer.fromColors(
          baseColor: base,
          highlightColor: highlight,
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Colors.white,
              radius: 22,
            ),
            title: Container(
              height: 14,
              margin: const EdgeInsets.only(right: 48),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                height: 12,
                margin: const EdgeInsets.only(right: 120),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
