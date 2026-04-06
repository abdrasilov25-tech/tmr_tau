import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../data/chat_giphy_catalog.dart';
import 'chat_sticker_picker_tab.dart';

/// Панель эмодзи / GIF / стикеров (как в WhatsApp / Telegram), вынесена для DM и групп.
class ChatRichEmojiPanel extends StatefulWidget {
  const ChatRichEmojiPanel({
    super.key,
    required this.onEmojiSelected,
    required this.onGifSelected,
    required this.onStickerEmojiSelected,
    required this.onStickerImageSelected,
    required this.onCreateStickerFromGallery,
    this.enableGifTab = true,
    this.enableStickerTab = true,
    this.height = 380,
  });

  final ValueChanged<String> onEmojiSelected;
  final ValueChanged<String> onGifSelected;
  final ValueChanged<String> onStickerEmojiSelected;
  final ValueChanged<String> onStickerImageSelected;
  final Future<void> Function() onCreateStickerFromGallery;
  final bool enableGifTab;
  final bool enableStickerTab;
  final double height;

  @override
  State<ChatRichEmojiPanel> createState() => _ChatRichEmojiPanelState();
}

class _ChatRichEmojiPanelState extends State<ChatRichEmojiPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  int _categoryIndex = 0;

  static const _categories = [
    ('😀', 'Смайлы'),
    ('🙌', 'Жесты'),
    ('❤️', 'Сердца'),
    ('🐶', 'Животные'),
    ('🍕', 'Еда'),
    ('⚽', 'Спорт'),
    ('✈️', 'Путешествия'),
  ];

  static const _emojiByCat = [
    ['😀','😃','😄','😁','😆','😅','🤣','😂','🙂','🙃','😉','😊','😇','🥰','😍','🤩','😘','😗','😚','😙','🥲','😋','😛','😜','🤪','😝','🤑','🤗','🤭','🤫','🤔','🤐','🤨','😐','😑','😶','😏','😒','🙄','😬','🤥','😌','😔','😪','🤤','😴','😷','🤒','🤕','🤢','🤧','🥵','🥶','🥴','😵','🤯','🤠','🥳','😎','🤓','🧐','😕','😟','🙁','☹️','😮','😯','😲','😳','🥺','😦','😧','😨','😰','😥','😢','😭','😱','😖','😣','😞','😓','😩','😫','🥱'],
    ['👋','🤚','🖐','✋','🖖','👌','🤌','🤏','✌️','🤞','🤟','🤘','🤙','👈','👉','👆','🖕','👇','☝️','👍','👎','✊','👊','🤛','🤜','👏','🙌','👐','🤲','🤝','🙏','✍️','💅','🤳','💪','🦾','🦿','🦵','🦶','👂','🦻','👃','🫀','🫁','🧠','🦷','🦴','👀','👁','👅','👄'],
    ['❤️','🧡','💛','💚','💙','💜','🖤','🤍','🤎','💔','❣️','💕','💞','💓','💗','💖','💘','💝','💟','☮️','✝️','☪️','🕉','✡️','🔯','🛐','⛎','♈','♉','♊','♋','♌','♍','♎','♏','♐','♑','♒','♓','🆔','⚛️','🉑','☢️','☣️','📴','📳','🈶','🈚','🈸','🈺','🈷️','✴️','🆚','💮','🉐','㊙️','㊗️','🈴','🈵','🈹','🈲','🅰️','🅱️','🆎','🆑','🅾️','🆘','❌','⭕','🛑','⛔','📛','🚫'],
    ['🐶','🐱','🐭','🐹','🐰','🦊','🐻','🐼','🐨','🐯','🦁','🐮','🐷','🐸','🐵','🙈','🙉','🙊','🐒','🐔','🐧','🐦','🐤','🦆','🦅','🦉','🦇','🐺','🐗','🐴','🦄','🐝','🪱','🐛','🦋','🐌','🐞','🐜','🪲','🦟','🦗','🕷','🦂','🐢','🐍','🦎','🦖','🦕','🐙','🦑','🦐','🦞','🦀','🐡','🐠','🐟','🐬','🐳','🐋','🦈','🦭','🐊','🐅','🐆','🦓','🦍','🦧','🦣','🐘','🦛','🦏','🐪','🐫','🦒','🦘','🦬','🐃','🐂','🐄','🐎','🐖','🐏','🐑','🦙','🐐','🦌','🐕','🐩','🦮','🐕‍🦺','🐈','🐈‍⬛','🪶','🐓','🦃','🦤','🦚','🦜','🦢','🦩','🕊','🐇','🦝','🦨','🦡','🦫','🦦','🦥','🐁','🐀','🐿','🦔'],
    ['🍏','🍎','🍐','🍊','🍋','🍌','🍉','🍇','🍓','🫐','🍈','🍒','🍑','🥭','🍍','🥥','🥝','🍅','🍆','🥑','🥦','🥬','🥒','🌶','🫑','🧄','🧅','🥔','🍠','🥐','🥯','🍞','🥖','🥨','🧀','🥚','🍳','🧈','🥞','🧇','🥓','🥩','🍗','🍖','🌭','🍔','🍟','🍕','🫓','🥪','🥙','🧆','🌮','🌯','🫔','🥗','🥘','🫕','🥫','🍝','🍜','🍲','🍛','🍣','🍱','🥟','🦪','🍤','🍙','🍚','🍘','🍥','🥮','🍢','🧁','🍰','🎂','🍮','🍭','🍬','🍫','🍿','🍩','🍪','🌰','🥜','🍯','🧃','🥤','🧋','🍵','☕','🫖','🍺','🍻','🥂','🍷','🥃','🍸','🍹','🧉','🍾','🧊','🥄','🍴','🍽','🥢','🧂'],
    ['⚽','🏀','🏈','⚾','🥎','🎾','🏐','🏉','🥏','🎱','🪀','🏓','🏸','🏒','🥍','🏏','🪃','🥅','⛳','🪁','🎣','🤿','🎽','🎿','🛷','🥌','🎯','🪀','🎮','🎲','♟','🎭','🎨','🎬','🎤','🎧','🎼','🎹','🥁','🪘','🎷','🎺','🎸','🪕','🎻','🎲','♟','🎯','🎳','🎰','🎪'],
    ['✈️','🚀','🛸','🚁','🛶','⛵','🚤','🛥','🛳','⛴','🚢','🚂','🚃','🚄','🚅','🚆','🚇','🚈','🚉','🚊','🚝','🚞','🚋','🚌','🚍','🚎','🏎','🚓','🚑','🚒','🚐','🛻','🚚','🚛','🚜','🏍','🛵','🛺','🚲','🛴'],
  ];

  int get _tabCount {
    var n = 1;
    if (widget.enableGifTab) n++;
    if (widget.enableStickerTab) n++;
    return n;
  }

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _tabCount, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Widget _emojiTabContent() {
    return Column(
          children: [
            SizedBox(
              height: 42,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                itemCount: _categories.length,
                itemBuilder: (_, i) {
                  final selected = i == _categoryIndex;
                  return GestureDetector(
                    onTap: () => setState(() => _categoryIndex = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: selected
                            ? Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        _categories[i].$1,
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                  );
                },
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(8),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 8,
                  childAspectRatio: 1,
                ),
                itemCount: _emojiByCat[_categoryIndex].length,
                itemBuilder: (_, i) {
                  final emoji = _emojiByCat[_categoryIndex][i];
                  return GestureDetector(
                    onTap: () => widget.onEmojiSelected(emoji),
                    child: Center(
                      child:
                          Text(emoji, style: const TextStyle(fontSize: 24)),
                    ),
                  );
                },
              ),
            ),
          ],
        );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        children: [
          TabBar(
            controller: _tab,
            labelColor: Theme.of(context).colorScheme.primary,
            unselectedLabelColor: Colors.grey.shade500,
            indicatorSize: TabBarIndicatorSize.tab,
            tabs: [
              const Tab(text: 'Эмодзи'),
              if (widget.enableGifTab) const Tab(text: 'GIF'),
              if (widget.enableStickerTab) const Tab(text: 'Стикеры'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _emojiTabContent(),
                if (widget.enableGifTab)
                  ChatGifCatalogTab(onGifSelected: widget.onGifSelected),
                if (widget.enableStickerTab)
                  ChatStickerPickerTab(
                    onEmojiSticker: widget.onStickerEmojiSelected,
                    onImageSticker: widget.onStickerImageSelected,
                    onCreateFromGallery: widget.onCreateStickerFromGallery,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Вкладка GIF (каталог как в Telegram).
class ChatGifCatalogTab extends StatefulWidget {
  const ChatGifCatalogTab({super.key, required this.onGifSelected});

  final ValueChanged<String> onGifSelected;

  @override
  State<ChatGifCatalogTab> createState() => _ChatGifCatalogTabState();
}

class _ChatGifCatalogTabState extends State<ChatGifCatalogTab> {
  final _searchController = TextEditingController();
  String _query = '';
  int _categoryIndex = 0;

  List<Map<String, String>> get _currentGifs {
    final cat = kChatGiphyCategories[_categoryIndex];
    final all = kChatGiphyCatalog[cat] ?? [];
    if (_query.isEmpty) return all;
    final q = _query.toLowerCase();
    return all
        .where((g) => (g['label'] ?? '').toLowerCase().contains(q))
        .toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gifs = _currentGifs;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
          child: TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _query = v),
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Поиск GIF...',
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              prefixIcon:
                  Icon(Icons.search, size: 18, color: Colors.grey.shade400),
              filled: true,
              fillColor: Colors.grey.shade100,
              contentPadding: const EdgeInsets.symmetric(vertical: 6),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        SizedBox(
          height: 36,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: kChatGiphyCategories.length,
            itemBuilder: (_, i) {
              final selected = i == _categoryIndex;
              return GestureDetector(
                onTap: () => setState(() => _categoryIndex = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(right: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: selected
                        ? Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey.shade300,
                    ),
                  ),
                  child: Text(
                    kChatGiphyCategories[i],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey.shade600,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: gifs.isEmpty
              ? Center(
                  child: Text(
                    'Ничего не найдено',
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                    childAspectRatio: 1,
                  ),
                  itemCount: gifs.length,
                  itemBuilder: (_, i) {
                    final gif = gifs[i];
                    final url = gif['url']!;
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => widget.onGifSelected(url),
                        borderRadius: BorderRadius.circular(8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl: url,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              color: Colors.grey.shade100,
                              child: const Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: Colors.grey.shade200,
                              child: Icon(Icons.gif_box_outlined,
                                  color: Colors.grey.shade400),
                            ),
                          ),
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
