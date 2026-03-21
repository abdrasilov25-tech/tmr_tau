import 'package:flutter/material.dart';
import '../../../../core/storage/multi_account_storage.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../auth/domain/entities/app_user.dart';

/// Нижняя панель переключения аккаунтов (как в Instagram): снизу вверх, круг с плюсом «Добавить аккаунт», список аккаунтов.
class AccountSwitcherSheet extends StatelessWidget {
  const AccountSwitcherSheet({
    super.key,
    required this.currentUser,
    required this.savedAccounts,
    required this.onAddAccount,
    required this.onSwitchAccount,
    this.scrollController,
  });

  final AppUser currentUser;
  final List<SavedAccount> savedAccounts;
  final VoidCallback onAddAccount;
  final void Function(SavedAccount account, VoidCallback closeSheet) onSwitchAccount;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final currentId = currentUser.id;
    final allAccounts = <SavedAccount>[
      SavedAccount(
        id: currentUser.id,
        email: currentUser.email,
        name: currentUser.name,
        avatarUrl: currentUser.avatarUrl,
      ),
      ...savedAccounts.where((a) => a.id != currentId),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            // Строка «Добавить аккаунт» — круг с плюсом + текст
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  Navigator.of(context).pop();
                  onAddAccount();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.grey.shade400, width: 2),
                          color: Colors.grey.shade100,
                        ),
                        child: const Icon(Icons.add, size: 28, color: Colors.black87),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Text(
                          'Добавить аккаунт в tmr_tau App',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.separated(
                controller: scrollController,
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: allAccounts.length,
                separatorBuilder: (context, index) =>
                    const Divider(height: 1, indent: 88),
                itemBuilder: (context, index) {
                  final account = allAccounts[index];
                  final isCurrent = account.id == currentId;
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: isCurrent
                          ? () => Navigator.of(context).pop()
                          : () => onSwitchAccount(account, () => Navigator.of(context).pop()),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        child: Row(
                          children: [
                            CachedAvatar(
                              imageUrl: account.avatarUrl,
                              radius: 28,
                              fallbackText: account.displayName,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    account.displayName,
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (account.email != account.displayName)
                                    Text(
                                      account.email,
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: Colors.grey.shade600,
                                          ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                            if (isCurrent)
                              Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary, size: 24),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
