import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/datasources/map_remote_datasource.dart';
import '../../domain/entities/sticker_pack.dart';

/// Sheet for browsing, buying sticker packs and assigning a sticker to a product.
class StickerPackSheet extends StatefulWidget {
  const StickerPackSheet({
    super.key,
    required this.dataSource,
    required this.productId,
    required this.productTitle,
    this.currentSticker,
    this.onStickerSet,
  });

  final MapRemoteDataSource dataSource;
  final String productId;
  final String productTitle;
  final String? currentSticker;
  final VoidCallback? onStickerSet;

  @override
  State<StickerPackSheet> createState() => _StickerPackSheetState();
}

class _StickerPackSheetState extends State<StickerPackSheet> {
  Set<String> _ownedPackIds = {};
  int? _balance;
  bool _loadingPackIds = true;
  String? _purchasingPackId;
  String? _settingSticker;
  String? _selectedSticker;

  @override
  void initState() {
    super.initState();
    _selectedSticker = widget.currentSticker;
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        widget.dataSource.getMyOwnedPackIds(),
        _fetchBalance(),
      ]);
      if (!mounted) return;
      setState(() {
        _ownedPackIds = (results[0] as List<String>).toSet();
        _loadingPackIds = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loadingPackIds = false);
    }
  }

  Future<int?> _fetchBalance() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return null;
      final row = await Supabase.instance.client
          .from('users')
          .select('qarmet_balance')
          .eq('id', uid)
          .maybeSingle();
      if (mounted) setState(() => _balance = (row?['qarmet_balance'] as num?)?.toInt());
    } catch (e) { debugPrint('$e'); }
    return null;
  }

  Future<void> _buyPack(String packId) async {
    setState(() => _purchasingPackId = packId);
    try {
      final newBalance = await widget.dataSource.purchaseStickerPack(packId);
      if (!mounted) return;
      setState(() {
        _ownedPackIds = {..._ownedPackIds, packId};
        _balance = newBalance;
        _purchasingPackId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Пак куплен! Выберите стикер для маркера.'),
          backgroundColor: Color(0xFF16A34A),
        ),
      );
    } on StickerPackException catch (e) {
      if (!mounted) return;
      setState(() => _purchasingPackId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.userMessage), backgroundColor: const Color(0xFFDC2626)),
      );
    } catch (e) {
      if (mounted) setState(() => _purchasingPackId = null);
    }
  }

  Future<void> _applySticker(String? sticker) async {
    setState(() => _settingSticker = sticker ?? '__clear__');
    try {
      await widget.dataSource.setProductMarkerSticker(widget.productId, sticker);
      if (!mounted) return;
      setState(() {
        _selectedSticker = sticker;
        _settingSticker = null;
      });
      widget.onStickerSet?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(sticker != null
              ? 'Стикер $sticker применён к маркеру!'
              : 'Стикер убран'),
          backgroundColor: const Color(0xFF16A34A),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _settingSticker = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text('🎨', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Стикер на маркере',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Text(widget.productTitle,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                if (_balance != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF9C3),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(children: [
                      const Icon(Icons.toll_rounded, size: 14, color: Color(0xFFF59E0B)),
                      const SizedBox(width: 4),
                      Text('$_balance Q',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600,
                              color: Color(0xFF92400E))),
                    ]),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (_selectedSticker != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF86EFAC)),
                ),
                child: Row(children: [
                  Text(_selectedSticker!, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('Активный стикер',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                  TextButton(
                    onPressed: _settingSticker != null ? null : () => _applySticker(null),
                    child: const Text('Убрать', style: TextStyle(color: Colors.red)),
                  ),
                ]),
              ),
            ),
          const SizedBox(height: 12),
          if (_loadingPackIds)
            const Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            )
          else
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Column(
                  children: StickerPackDefinition.all.map((pack) {
                    final owned = _ownedPackIds.contains(pack.id);
                    final buying = _purchasingPackId == pack.id;
                    return _PackCard(
                      pack: pack,
                      owned: owned,
                      buying: buying,
                      selectedSticker: _selectedSticker,
                      settingSticker: _settingSticker,
                      onBuy: () => _buyPack(pack.id),
                      onStickerTap: owned ? _applySticker : null,
                    );
                  }).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PackCard extends StatelessWidget {
  const _PackCard({
    required this.pack,
    required this.owned,
    required this.buying,
    required this.selectedSticker,
    required this.settingSticker,
    required this.onBuy,
    this.onStickerTap,
  });

  final StickerPackDefinition pack;
  final bool owned;
  final bool buying;
  final String? selectedSticker;
  final String? settingSticker;
  final VoidCallback onBuy;
  final void Function(String)? onStickerTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: owned ? const Color(0xFFF8FAFF) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: owned ? const Color(0xFF93C5FD) : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(pack.emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(pack.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  if (pack.isLimited) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF9C3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('LIMITED',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold,
                              color: Color(0xFF92400E))),
                    ),
                  ],
                ]),
                Text('${pack.stickers.length} стикеров',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ]),
            ),
            if (!owned)
              GestureDetector(
                onTap: buying ? null : onBuy,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: buying
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('${StickerPackDefinition.costQarmet} Q',
                          style: const TextStyle(color: Colors.white,
                              fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('Куплен ✓',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                        color: Color(0xFF166534))),
              ),
          ]),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: pack.stickers.map((s) {
              final isActive = selectedSticker == s;
              final isSetting = settingSticker == s;
              return GestureDetector(
                onTap: owned && onStickerTap != null && !isSetting
                    ? () => onStickerTap!(s)
                    : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: isActive
                        ? const Color(0xFF2563EB).withValues(alpha: 0.12)
                        : owned ? Colors.white : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isActive
                          ? const Color(0xFF2563EB)
                          : owned ? Colors.grey.shade200 : Colors.transparent,
                      width: isActive ? 2 : 1,
                    ),
                  ),
                  child: isSetting
                      ? const Center(child: SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)))
                      : Center(
                          child: Text(s,
                              style: TextStyle(
                                  fontSize: 24,
                                  color: owned ? null : Colors.grey.shade300)),
                        ),
                ),
              );
            }).toList(),
          ),
          if (!owned)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Купите пак чтобы выбрать стикер',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
            ),
        ],
      ),
    );
  }
}
