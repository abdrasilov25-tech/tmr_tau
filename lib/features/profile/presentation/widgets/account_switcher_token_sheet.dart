import 'package:flutter/material.dart';

import '../../../../core/accounts/account_model.dart';
import '../../../../core/storage/multi_account_storage.dart';
import '../../../../core/widgets/cached_avatar.dart';

class AccountSwitcherTokenSheet extends StatelessWidget {
  const AccountSwitcherTokenSheet({
    super.key,
    required this.activeAccount,
    required this.accounts,
    required this.savedAccounts,
    required this.onSelectAccount,
    required this.onAddAccount,
    required this.scrollController,
  });

  final AccountModel? activeAccount;
  final List<AccountModel> accounts;
  final List<SavedAccount> savedAccounts;
  final void Function(AccountModel) onSelectAccount;
  final VoidCallback onAddAccount;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final otherAccounts = accounts
        .where(
          (a) => activeAccount == null || a.userId != activeAccount!.userId,
        )
        .toList();

    SavedAccount? findSaved(AccountModel acc) {
      for (final s in savedAccounts) {
        if (s.id == acc.userId || s.email == acc.email) return s;
      }
      return null;
    }

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Аккаунты',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                TextButton(
                  onPressed: onAddAccount,
                  child: const Text('+ Добавить'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: scrollController,
              children: [
                if (activeAccount != null)
                  Builder(
                    builder: (context) {
                      final saved = findSaved(activeAccount!);
                      final username = activeAccount!.username;
                      final primary = (username != null &&
                              username.isNotEmpty)
                          ? '@$username'
                          : (saved?.displayName ?? activeAccount!.email);
                      final originalUrl = saved?.avatarUrl;
                      final avatarUrl = (originalUrl != null &&
                              originalUrl.isNotEmpty)
                          ? '$originalUrl?uid=${activeAccount!.userId}'
                          : null;
                      return ListTile(
                        leading: CachedAvatar(
                          imageUrl: avatarUrl,
                          radius: 20,
                          fallbackText: primary,
                        ),
                        title: Text(
                          primary,
                          style:
                              const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text('Текущий аккаунт'),
                      );
                    },
                  ),
                for (final a in otherAccounts)
                  Builder(
                    builder: (context) {
                      final saved = findSaved(a);
                      final username = a.username;
                      final primary = (username != null &&
                              username.isNotEmpty)
                          ? '@$username'
                          : (saved?.displayName ?? a.email);
                      final originalUrl = saved?.avatarUrl;
                      final avatarUrl = (originalUrl != null &&
                              originalUrl.isNotEmpty)
                          ? '$originalUrl?uid=${a.userId}'
                          : null;
                      return ListTile(
                        leading: CachedAvatar(
                          imageUrl: avatarUrl,
                          radius: 20,
                          fallbackText: primary,
                        ),
                        title: Text(primary),
                        onTap: () => onSelectAccount(a),
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

