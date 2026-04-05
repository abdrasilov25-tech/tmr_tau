import 'package:flutter/material.dart';

import '../../domain/entities/story_overlay_item.dart';
import '../utils/story_sticker_pick_helpers.dart';

/// Instagram-подобная панель стикеров для экрана создания сторис.
///
/// [anchorContext] — контекст экрана редактора (диалоги после закрытия листа).
Future<void> showStoryStickersTray(
  BuildContext context, {
  required BuildContext anchorContext,
  required Future<void> Function() onMusic,
  required bool musicEnabled,
  required void Function(StoryOverlayItem item) onAddOverlay,
  String? userAvatarUrl,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (ctx) => _StoryStickersTrayBody(
      anchorContext: anchorContext,
      onMusic: onMusic,
      musicEnabled: musicEnabled,
      onAddOverlay: onAddOverlay,
      userAvatarUrl: userAvatarUrl,
    ),
  );
}

class _StickerDef {
  const _StickerDef({
    required this.id,
    required this.label,
    required this.icon,
    required this.accent,
  });

  final String id;
  final String label;
  final IconData icon;
  final Color accent;
}

class _StoryStickersTrayBody extends StatefulWidget {
  const _StoryStickersTrayBody({
    required this.anchorContext,
    required this.onMusic,
    required this.musicEnabled,
    required this.onAddOverlay,
    this.userAvatarUrl,
  });

  final BuildContext anchorContext;
  final Future<void> Function() onMusic;
  final bool musicEnabled;
  final void Function(StoryOverlayItem item) onAddOverlay;
  final String? userAvatarUrl;

  @override
  State<_StoryStickersTrayBody> createState() => _StoryStickersTrayBodyState();
}

class _StoryStickersTrayBodyState extends State<_StoryStickersTrayBody> {
  final _search = TextEditingController();

  static const List<_StickerDef> _all = [
    _StickerDef(
      id: 'location',
      label: 'Местоположение',
      icon: Icons.location_on_rounded,
      accent: Color(0xFF833AB4),
    ),
    _StickerDef(
      id: 'mention',
      label: '@упоминание',
      icon: Icons.alternate_email_rounded,
      accent: Color(0xFFFF9800),
    ),
    _StickerDef(
      id: 'music',
      label: 'Музыка',
      icon: Icons.music_note_rounded,
      accent: Color(0xFFE91E8C),
    ),
    _StickerDef(
      id: 'photo',
      label: 'Фото',
      icon: Icons.image_rounded,
      accent: Color(0xFF4CAF50),
    ),
    _StickerDef(
      id: 'gif',
      label: 'GIF',
      icon: Icons.browse_gallery_rounded,
      accent: Color(0xFF2196F3),
    ),
    _StickerDef(
      id: 'yours',
      label: 'Ваш ответ',
      icon: Icons.add_a_photo_rounded,
      accent: Color(0xFFE91E8C),
    ),
    _StickerDef(
      id: 'frames',
      label: 'Рамки',
      icon: Icons.filter_frames_rounded,
      accent: Color(0xFF9C27B0),
    ),
    _StickerDef(
      id: 'questions',
      label: 'Вопросы',
      icon: Icons.help_outline_rounded,
      accent: Color(0xFF7C4DFF),
    ),
    _StickerDef(
      id: 'cutouts',
      label: 'Вырезки',
      icon: Icons.content_cut_rounded,
      accent: Color(0xFF4CAF50),
    ),
    _StickerDef(
      id: 'trending',
      label: 'Актуальное',
      icon: Icons.whatshot_rounded,
      accent: Color(0xFFE91E8C),
    ),
    _StickerDef(
      id: 'notify',
      label: 'Уведомить',
      icon: Icons.notifications_active_rounded,
      accent: Color(0xFF2196F3),
    ),
    _StickerDef(
      id: 'avatar',
      label: 'Аватар',
      icon: Icons.face_rounded,
      accent: Color(0xFFFF9800),
    ),
    _StickerDef(
      id: 'poll',
      label: 'Опрос',
      icon: Icons.poll_rounded,
      accent: Color(0xFFE91E8C),
    ),
    _StickerDef(
      id: 'slider',
      label: 'Шкала',
      icon: Icons.linear_scale_rounded,
      accent: Color(0xFFFF4081),
    ),
    _StickerDef(
      id: 'link',
      label: 'Ссылка',
      icon: Icons.link_rounded,
      accent: Color(0xFF2196F3),
    ),
    _StickerDef(
      id: 'hashtag',
      label: '#хэштег',
      icon: Icons.tag_rounded,
      accent: Color(0xFF833AB4),
    ),
    _StickerDef(
      id: 'countdown',
      label: 'Обратный отсчёт',
      icon: Icons.timer_outlined,
      accent: Color(0xFF7C4DFF),
    ),
    _StickerDef(
      id: 'text',
      label: 'Текст',
      icon: Icons.text_fields_rounded,
      accent: Color(0xFFFF9800),
    ),
    _StickerDef(
      id: 'food',
      label: 'Заказы еды',
      icon: Icons.delivery_dining_rounded,
      accent: Color(0xFFE53935),
    ),
  ];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _snackAnchor(String text) {
    if (!widget.anchorContext.mounted) return;
    ScaffoldMessenger.of(widget.anchorContext).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> _onChipTap(_StickerDef def) async {
    final sheetNav = Navigator.of(context);
    final host = widget.anchorContext;

    switch (def.id) {
      case 'music':
        if (!widget.musicEnabled) {
          _snackAnchor('Музыка доступна в режиме «История» или «Видео»');
          return;
        }
        sheetNav.pop();
        await widget.onMusic();
        return;
      case 'frames':
        sheetNav.pop();
        widget.onAddOverlay(StoryStickerPickHelpers.addFrame());
        return;
      case 'avatar':
        final a = StoryStickerPickHelpers.addAvatarSticker(widget.userAvatarUrl);
        if (a == null) {
          _snackAnchor('Нет аватара в профиле');
          return;
        }
        sheetNav.pop();
        widget.onAddOverlay(a);
        return;
    }

    sheetNav.pop();
    await Future<void>.delayed(Duration.zero);
    if (!host.mounted) return;

    StoryOverlayItem? item;
    switch (def.id) {
      case 'location':
        item = await StoryStickerPickHelpers.addLocation(host);
        break;
      case 'mention':
        item = await StoryStickerPickHelpers.addMention(host);
        break;
      case 'photo':
        item = await StoryStickerPickHelpers.addPhotoSticker(host);
        break;
      case 'gif':
        item = await StoryStickerPickHelpers.addGifSticker(host);
        break;
      case 'yours':
        item = await StoryStickerPickHelpers.addAddYours(host);
        break;
      case 'questions':
        item = await StoryStickerPickHelpers.addQuestion(host);
        break;
      case 'cutouts':
        item = await StoryStickerPickHelpers.addCutout(host);
        break;
      case 'trending':
        item = await StoryStickerPickHelpers.addTrending(host);
        break;
      case 'notify':
        item = await StoryStickerPickHelpers.addNotify(host);
        break;
      case 'poll':
        item = await StoryStickerPickHelpers.addPoll(host);
        break;
      case 'slider':
        item = await StoryStickerPickHelpers.addSlider(host);
        break;
      case 'link':
        item = await StoryStickerPickHelpers.addLink(host);
        break;
      case 'hashtag':
        item = await StoryStickerPickHelpers.addHashtag(host);
        break;
      case 'countdown':
        item = await StoryStickerPickHelpers.addCountdown(host);
        break;
      case 'text':
        item = await StoryStickerPickHelpers.addText(host);
        break;
      case 'food':
        item = await StoryStickerPickHelpers.addFood(host);
        break;
      default:
        break;
    }
    if (item != null && host.mounted) {
      widget.onAddOverlay(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottom = mq.padding.bottom + mq.viewInsets.bottom;
    final q = _search.text.trim().toLowerCase();
    final filtered = q.isEmpty
        ? _all
        : _all
            .where(
              (e) =>
                  e.label.toLowerCase().contains(q) ||
                  e.id.contains(q),
            )
            .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.38,
      maxChildSize: 0.94,
      expand: false,
      builder: (ctx, scrollController) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E).withValues(alpha: 0.97),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  cursorColor: Colors.white,
                  decoration: InputDecoration(
                    hintText: 'Поиск',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                    filled: true,
                    fillColor: const Color(0xFF2C2C2E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.fromLTRB(12, 0, 12, bottom + 16),
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: filtered
                          .map(
                            (def) => _StickerChip(
                              def: def,
                              onTap: () => _onChipTap(def),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Декор',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _DecorStub(
                          label: '16 25',
                          child: Text(
                            '16 25',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                        _DecorStub(
                          label: '13°C',
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.wb_sunny_rounded,
                                color: Colors.amber.shade200,
                                size: 22,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '13°C',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _DecorStub(
                          label: '♥',
                          child: Icon(
                            Icons.favorite_rounded,
                            color: Colors.lightBlueAccent,
                            size: 32,
                          ),
                        ),
                        _DecorStub(
                          label: '❤',
                          child: Icon(
                            Icons.favorite_rounded,
                            color: Colors.purple.shade200,
                            size: 32,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StickerChip extends StatelessWidget {
  const _StickerChip({
    required this.def,
    required this.onTap,
  });

  final _StickerDef def;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: def.accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(def.icon, color: def.accent, size: 20),
              ),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(
                  def.label,
                  style: const TextStyle(
                    color: Color(0xFF121212),
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DecorStub extends StatelessWidget {
  const _DecorStub({
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: child,
      ),
    );
  }
}
