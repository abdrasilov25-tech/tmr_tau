import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/chat_sticker_emoji_packs.dart';
import '../../data/chat_sticker_favorites_storage.dart';

/// DM sticker tab: create from gallery, favorites, packs, star toggle.
class ChatStickerPickerTab extends StatefulWidget {
  const ChatStickerPickerTab({
    super.key,
    required this.onEmojiSticker,
    required this.onImageSticker,
    required this.onCreateFromGallery,
  });

  final ValueChanged<String> onEmojiSticker;
  final ValueChanged<String> onImageSticker;
  final Future<void> Function() onCreateFromGallery;

  @override
  State<ChatStickerPickerTab> createState() => _ChatStickerPickerTabState();
}

class _ChatStickerPickerTabState extends State<ChatStickerPickerTab> {
  int _categoryIndex = 0;

  static String? _parseFavorite(String raw) {
    if (raw.startsWith('e:')) return raw.substring(2);
    if (raw.startsWith('u:')) return raw.substring(2);
    return null;
  }

  static bool _isEmojiEntry(String raw) => raw.startsWith('e:');

  @override
  Widget build(BuildContext context) {
    final fav = context.watch<ChatStickerFavoritesStorage>();
    final favorites = fav.rawEntries;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
          child: OutlinedButton.icon(
            onPressed: () => widget.onCreateFromGallery(),
            icon: const Icon(Icons.auto_fix_high_rounded, size: 20),
            label: const Text('Создать из фото'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
        if (favorites.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
            child: Text(
              'Избранное',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          SizedBox(
            height: 76,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              scrollDirection: Axis.horizontal,
              itemCount: favorites.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final token = favorites[i];
                final payload = _parseFavorite(token);
                if (payload == null) return const SizedBox.shrink();
                return Material(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    onTap: () {
                      if (_isEmojiEntry(token)) {
                        widget.onEmojiSticker(payload);
                      } else {
                        widget.onImageSticker(payload);
                      }
                    },
                    onLongPress: () => fav.removeToken(token),
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      width: 72,
                      height: 72,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: _isEmojiEntry(token)
                                  ? Center(
                                      child: Text(
                                        payload,
                                        style: const TextStyle(fontSize: 44),
                                      ),
                                    )
                                  : ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: CachedNetworkImage(
                                        imageUrl: payload,
                                        fit: BoxFit.contain,
                                        placeholder: (context, url) =>
                                            const Center(
                                          child: SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                        ),
                                        errorWidget:
                                            (context, url, error) => Icon(
                                          Icons.broken_image_outlined,
                                          color: Colors.grey.shade400,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                          Positioned(
                            top: 2,
                            right: 2,
                            child: GestureDetector(
                              onTap: () => fav.removeToken(token),
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.close_rounded,
                                  size: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
        ],
        SizedBox(
          height: 40,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: kStickerPackLabels.length,
            itemBuilder: (_, i) {
              final selected = i == _categoryIndex;
              return GestureDetector(
                onTap: () => setState(() => _categoryIndex = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(right: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: selected
                        ? Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(
                      kStickerPackLabels[i],
                      style: TextStyle(
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 13,
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey.shade600,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              childAspectRatio: 0.92,
            ),
            itemCount: kStickerEmojiPacks[_categoryIndex].length,
            itemBuilder: (_, i) {
              final emoji = kStickerEmojiPacks[_categoryIndex][i];
              final token = ChatStickerFavoritesStorage.tokenEmoji(emoji);
              final isFav = fav.isFavoriteToken(token);
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => widget.onEmojiSticker(emoji),
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Center(
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 52),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          iconSize: 20,
                          onPressed: () => fav.toggleToken(token),
                          icon: Icon(
                            isFav ? Icons.star_rounded : Icons.star_outline_rounded,
                            color: isFav
                                ? Colors.amber.shade700
                                : Colors.grey.shade400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
