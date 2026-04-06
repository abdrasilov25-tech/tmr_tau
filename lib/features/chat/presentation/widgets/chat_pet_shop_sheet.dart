import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/wow_entry_overlay.dart';

import '../../../../features/product/presentation/bloc/payment_cubit.dart';
import '../../data/chat_pets_storage.dart';
import '../../data/chat_streak_storage.dart';
import '../../domain/entities/chat_pet.dart';

/// Beautiful pet shop bottom sheet for DM gamification.
/// Opens when the user taps the pet avatar/badge in a DM chat.
class ChatPetShopSheet extends StatefulWidget {
  const ChatPetShopSheet({
    super.key,
    required this.peerId,
    required this.currentUserId,
  });

  final String peerId;
  final String currentUserId;

  static Future<void> show(
    BuildContext context, {
    required String peerId,
    required String currentUserId,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChatPetShopSheet(
        peerId: peerId,
        currentUserId: currentUserId,
      ),
    );
  }

  @override
  State<ChatPetShopSheet> createState() => _ChatPetShopSheetState();
}

class _ChatPetShopSheetState extends State<ChatPetShopSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;
  bool _purchasing = false;
  OverlayEntry? _toastEntry;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _removeToastEntry();
    _shimmerController.dispose();
    super.dispose();
  }

  void _removeToastEntry() {
    final e = _toastEntry;
    _toastEntry = null;
    if (e != null && e.mounted) e.remove();
  }

  /// Видно поверх bottom sheet (в отличие от SnackBar снизу).
  void _showTopPetNotice({
    required String message,
    required Color backgroundColor,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    if (!mounted) return;
    _removeToastEntry();
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      ScaffoldMessenger.of(context).showMaterialBanner(
        MaterialBanner(
          content: Text(message),
          backgroundColor: backgroundColor,
          actions: [
            if (actionLabel != null && onAction != null)
              TextButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
                  onAction();
                },
                child: Text(actionLabel, style: const TextStyle(color: Colors.white)),
              )
            else
              TextButton(
                onPressed: () =>
                    ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
                child: const Text('OK', style: TextStyle(color: Colors.white)),
              ),
          ],
        ),
      );
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
        }
      });
      return;
    }

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _AnimatedTopPetBanner(
        message: message,
        backgroundColor: backgroundColor,
        actionLabel: actionLabel,
        onAction: onAction,
        onDismissComplete: () {
          if (entry.mounted) entry.remove();
          if (_toastEntry == entry) _toastEntry = null;
        },
      ),
    );
    _toastEntry = entry;
    overlay.insert(entry);
  }

  ChatStreakStorage get _streakStorage => context.read<ChatStreakStorage>();
  ChatPetsStorage get _petsStorage => context.read<ChatPetsStorage>();

  int get _streak => _streakStorage.getStreak(widget.peerId);
  bool get _hasFreePet => _streak >= 3;
  Set<String> get _owned => _petsStorage.getOwnedPets();
  String? get _activePet => _petsStorage.getActivePet(widget.peerId);

  Future<void> _claimFreePet() async {
    if (_purchasing) return;
    setState(() => _purchasing = true);
    try {
      await _petsStorage.addOwnedPet('seriychik');
      await _petsStorage.setActivePet(widget.peerId, 'seriychik');
      if (!mounted) return;
      setState(() => _purchasing = false);
      _showSuccess('Серийчик теперь ваш!');
    } catch (e) {
      if (!mounted) return;
      setState(() => _purchasing = false);
    }
  }

  Future<void> _buyPet(ChatPetDefinition pet) async {
    if (_purchasing) return;
    final cubit = context.read<PaymentCubit>();
    final balance = cubit.state.balance;
    if (balance < pet.price) {
      _showInsufficientFunds(pet.price, balance);
      return;
    }

    final confirmed = await _showConfirmDialog(pet);
    if (!confirmed || !mounted) return;

    setState(() => _purchasing = true);
    final success = await cubit.purchaseChatPet(
      petId: pet.id,
      cost: pet.price,
    );
    if (!mounted) return;

    if (success) {
      await _petsStorage.addOwnedPet(pet.id);
      await _petsStorage.setActivePet(widget.peerId, pet.id);
      if (!mounted) return;
      setState(() => _purchasing = false);
      _showSuccess('${pet.emoji} ${pet.name} теперь ваш!');
    } else {
      setState(() => _purchasing = false);
    }
  }

  Future<void> _activatePet(ChatPetDefinition pet) async {
    await _petsStorage.setActivePet(widget.peerId, pet.id);
    if (!mounted) return;
    setState(() {});
    _showSuccess('${pet.emoji} ${pet.name} активирован!');
  }

  Future<void> _deactivatePet() async {
    await _petsStorage.clearActivePet(widget.peerId);
    if (!mounted) return;
    setState(() {});
  }

  Future<bool> _showConfirmDialog(ChatPetDefinition pet) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: pet.gradientColors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: pet.gradientColors.last.withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    pet.emoji,
                    style: const TextStyle(fontSize: 34),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Купить ${pet.name}?',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('⭐', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 4),
                  Text(
                    '${pet.price} Qarmet',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.amber.shade700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Отмена'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: pet.gradientColors.first,
                      ),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Купить'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return result == true;
  }

  void _showSuccess(String message) {
    _showTopPetNotice(
      message: message,
      backgroundColor: const Color(0xFF22C55E),
    );
  }

  void _showInsufficientFunds(int required, int balance) {
    _showTopPetNotice(
      message: 'Не хватает Qarmet. Нужно: $required, у вас: $balance',
      backgroundColor: const Color(0xFFEF4444),
      actionLabel: 'Пополнить',
      onAction: () {
        final router = GoRouter.maybeOf(context);
        if (!mounted) return;
        Navigator.of(context).pop();
        if (router != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            router.push('/qarmet-wallet');
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaHeight = MediaQuery.of(context).size.height;
    return WowEntryOverlay(
      type: WowEntryType.shop,
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (ctx, scrollController) => _ShopBody(
          scrollController: scrollController,
          streak: _streak,
          hasFreePet: _hasFreePet,
          owned: _owned,
          activePet: _activePet,
          shimmerController: _shimmerController,
          purchasing: _purchasing,
          onClaimFreePet: _claimFreePet,
          onBuyPet: _buyPet,
          onActivatePet: _activatePet,
          onDeactivate: _deactivatePet,
          mediaHeight: mediaHeight,
        ),
      ),
    );
  }
}

/// Уведомление сверху экрана с анимацией (для магазина питомцев в modal sheet).
class _AnimatedTopPetBanner extends StatefulWidget {
  const _AnimatedTopPetBanner({
    required this.message,
    required this.backgroundColor,
    this.actionLabel,
    this.onAction,
    required this.onDismissComplete,
  });

  final String message;
  final Color backgroundColor;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDismissComplete;

  @override
  State<_AnimatedTopPetBanner> createState() =>
      _AnimatedTopPetBannerState();
}

class _AnimatedTopPetBannerState extends State<_AnimatedTopPetBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;
  Timer? _autoHide;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.35),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));
    _fade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _c, curve: Curves.easeOut),
    );
    _c.forward().then((_) {
      if (!mounted) return;
      _autoHide = Timer(const Duration(seconds: 3), _dismiss);
    });
  }

  void _dismiss() {
    _autoHide?.cancel();
    _autoHide = null;
    if (!mounted) return;
    _c.reverse().then((_) {
      if (mounted) widget.onDismissComplete();
    });
  }

  void _onActionTap() {
    _autoHide?.cancel();
    if (!mounted) return;
    widget.onAction?.call();
    widget.onDismissComplete();
  }

  @override
  void dispose() {
    _autoHide?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return Positioned(
      top: pad.top + 8,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: Material(
            elevation: 10,
            borderRadius: BorderRadius.circular(14),
            color: widget.backgroundColor,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        height: 1.25,
                      ),
                    ),
                  ),
                  if (widget.actionLabel != null && widget.onAction != null) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _onActionTap,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      child: Text(
                        widget.actionLabel!,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShopBody extends StatelessWidget {
  const _ShopBody({
    required this.scrollController,
    required this.streak,
    required this.hasFreePet,
    required this.owned,
    required this.activePet,
    required this.shimmerController,
    required this.purchasing,
    required this.onClaimFreePet,
    required this.onBuyPet,
    required this.onActivatePet,
    required this.onDeactivate,
    required this.mediaHeight,
  });

  final ScrollController scrollController;
  final int streak;
  final bool hasFreePet;
  final Set<String> owned;
  final String? activePet;
  final AnimationController shimmerController;
  final bool purchasing;
  final VoidCallback onClaimFreePet;
  final Future<void> Function(ChatPetDefinition) onBuyPet;
  final Future<void> Function(ChatPetDefinition) onActivatePet;
  final VoidCallback onDeactivate;
  final double mediaHeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F0F23), Color(0xFF1A1040), Color(0xFF0D1B2A)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // ─── Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ─── Header
          _buildHeader(context),

          const SizedBox(height: 4),

          // ─── Content
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              children: [
                if (hasFreePet) ...[
                  _FreePetCard(
                    owned: owned.contains('seriychik'),
                    isActive: activePet == 'seriychik',
                    onClaim: onClaimFreePet,
                    onActivate: () {
                      final pet = petById('seriychik');
                      if (pet != null) onActivatePet(pet);
                    },
                    purchasing: purchasing,
                  ),
                  const SizedBox(height: 20),
                ],

                // Section: Premium Pets
                _SectionLabel(
                  icon: '✨',
                  title: 'Каталог питомцев',
                  subtitle: 'Уникальный скин только в этом чате',
                ),
                const SizedBox(height: 12),

                // Pet grid (paid pets)
                _PetGrid(
                  pets: kChatPetCatalog.where((p) => !p.isFree).toList(),
                  owned: owned,
                  activePet: activePet,
                  onBuy: onBuyPet,
                  onActivate: onActivatePet,
                  onDeactivate: onDeactivate,
                  purchasing: purchasing,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Row(
        children: [
          // Shop icon
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF6B6B), Color(0xFFFF8E53)],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF6B6B).withValues(alpha: 0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Center(
              child: Text('🏪', style: TextStyle(fontSize: 22)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Магазин питомцев',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Покажи питомца только здесь',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          // Streak badge
          _StreakBadge(streak: streak),
        ],
      ),
    );
  }
}

/// Streak flame badge shown in the shop header.
class _StreakBadge extends StatelessWidget {
  const _StreakBadge({required this.streak});
  final int streak;

  @override
  Widget build(BuildContext context) {
    if (streak == 0) return const SizedBox.shrink();
    final flames = streak >= 30
        ? '🔥🔥🔥'
        : streak >= 14
        ? '🔥🔥'
        : '🔥';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF6B35), Color(0xFFFF4500)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF4500).withValues(alpha: 0.4),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(flames, style: const TextStyle(fontSize: 14)),
          Text(
            '$streak дн',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Card for the free Серийчик pet (unlocked at 3-day streak).
class _FreePetCard extends StatelessWidget {
  const _FreePetCard({
    required this.owned,
    required this.isActive,
    required this.onClaim,
    required this.onActivate,
    required this.purchasing,
  });

  final bool owned;
  final bool isActive;
  final VoidCallback onClaim;
  final VoidCallback onActivate;
  final bool purchasing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E3A5F), Color(0xFF2D1B69)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFFF9A56).withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF9A56).withValues(alpha: 0.15),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        children: [
          // Pet avatar
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF9A56), Color(0xFFFF6B35)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF6B35).withValues(alpha: 0.5),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: const Center(
              child: Text('🐱', style: TextStyle(fontSize: 32)),
            ),
          ),
          const SizedBox(width: 16),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Серийчик',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'БЕСПЛАТНО',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Бесплатный питомец за 3+ дня переписки',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                if (!owned)
                  _ActionButton(
                    label: 'Получить бесплатно',
                    icon: '🎁',
                    color: const Color(0xFF22C55E),
                    onTap: purchasing ? null : onClaim,
                  )
                else if (isActive)
                  _ActiveLabel()
                else
                  _ActionButton(
                    label: 'Активировать',
                    icon: '✨',
                    color: const Color(0xFFFF9A56),
                    onTap: onActivate,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: onTap == null ? 0.3 : 1.0),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveLabel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF22C55E), width: 1.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('✅', style: TextStyle(fontSize: 12)),
          SizedBox(width: 5),
          Text(
            'Активен',
            style: TextStyle(
              color: Color(0xFF22C55E),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final String icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Padding(
          padding: const EdgeInsets.only(left: 26),
          child: Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}

class _PetGrid extends StatelessWidget {
  const _PetGrid({
    required this.pets,
    required this.owned,
    required this.activePet,
    required this.onBuy,
    required this.onActivate,
    required this.onDeactivate,
    required this.purchasing,
  });

  final List<ChatPetDefinition> pets;
  final Set<String> owned;
  final String? activePet;
  final Future<void> Function(ChatPetDefinition) onBuy;
  final Future<void> Function(ChatPetDefinition) onActivate;
  final VoidCallback onDeactivate;
  final bool purchasing;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.72,
      ),
      itemCount: pets.length,
      itemBuilder: (ctx, i) {
        final pet = pets[i];
        final isOwned = owned.contains(pet.id);
        final isActive = activePet == pet.id;
        return _PetCard(
          pet: pet,
          isOwned: isOwned,
          isActive: isActive,
          onTap: purchasing
              ? null
              : () {
                  if (!isOwned) {
                    onBuy(pet);
                  } else if (isActive) {
                    onDeactivate();
                  } else {
                    onActivate(pet);
                  }
                },
        );
      },
    );
  }
}

class _PetCard extends StatelessWidget {
  const _PetCard({
    required this.pet,
    required this.isOwned,
    required this.isActive,
    required this.onTap,
  });

  final ChatPetDefinition pet;
  final bool isOwned;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isActive
                ? [
                    pet.gradientColors.first,
                    pet.gradientColors.last,
                  ]
                : [
                    pet.gradientColors.first.withValues(alpha: 0.3),
                    pet.gradientColors.last.withValues(alpha: 0.2),
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isActive
                ? pet.gradientColors.first
                : pet.gradientColors.first.withValues(alpha: 0.3),
            width: isActive ? 2 : 1,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: pet.gradientColors.first.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 8),
            // Emoji
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(
                      pet.emoji,
                      style: const TextStyle(fontSize: 28),
                    ),
                  ),
                ),
                if (isOwned && !isActive)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: const BoxDecoration(
                        color: Color(0xFF22C55E),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Text(
                          '✓',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (isActive)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: const BoxDecoration(
                        color: Colors.amber,
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Text(
                          '★',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // Name
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                pet.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isActive
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.85),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 6),
            // Price / status button
            _PriceChip(
              pet: pet,
              isOwned: isOwned,
              isActive: isActive,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _PriceChip extends StatelessWidget {
  const _PriceChip({
    required this.pet,
    required this.isOwned,
    required this.isActive,
  });

  final ChatPetDefinition pet;
  final bool isOwned;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    if (isActive) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          'Активен',
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    if (isOwned) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF22C55E).withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          '✓ Куплен',
          style: TextStyle(
            color: Color(0xFF86EFAC),
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            pet.gradientColors.first.withValues(alpha: 0.7),
            pet.gradientColors.last.withValues(alpha: 0.7),
          ],
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('⭐', style: TextStyle(fontSize: 9)),
          const SizedBox(width: 2),
          Text(
            '${pet.price}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
