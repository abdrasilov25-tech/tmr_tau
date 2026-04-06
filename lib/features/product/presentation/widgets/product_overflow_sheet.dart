import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/product_entity.dart';

/// Три точки на карточке товара: ссылка, жалоба, заблокировать продавца (как в ленте).
Future<void> showProductOverflowSheet(
  BuildContext context, {
  required ProductEntity product,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.link_outlined),
            title: const Text('Скопировать ссылку'),
            onTap: () {
              Clipboard.setData(
                ClipboardData(text: 'https://tmrtau.kz/product/${product.id}'),
              );
              Navigator.pop(sheetCtx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Ссылка скопирована'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.flag_outlined, color: Colors.red.shade700),
            title: Text(
              'Пожаловаться на объявление',
              style: TextStyle(color: Colors.red.shade700),
            ),
            onTap: () {
              Navigator.pop(sheetCtx);
              _showProductReportReasons(context, product);
            },
          ),
          ListTile(
            leading: Icon(Icons.block_rounded, color: Colors.red.shade700),
            title: Text(
              'Заблокировать продавца',
              style: TextStyle(color: Colors.red.shade700),
            ),
            onTap: () {
              Navigator.pop(sheetCtx);
              _confirmBlockSeller(context, product);
            },
          ),
          ListTile(
            leading: const Icon(Icons.support_agent_outlined),
            title: const Text('Написать в поддержку'),
            onTap: () {
              Navigator.pop(sheetCtx);
              context.push('/profile/settings/report-problem');
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

void _confirmBlockSeller(BuildContext context, ProductEntity product) {
  showDialog<void>(
    context: context,
    builder: (dlgCtx) => AlertDialog(
      title: Text('Заблокировать ${product.sellerName ?? 'продавца'}?'),
      content: const Text(
        'Вы сможете меньше видеть этого продавца в рекомендациях.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dlgCtx),
          child: const Text('Отмена'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
          onPressed: () {
            Navigator.pop(dlgCtx);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${product.sellerName ?? 'Продавец'} заблокирован',
                ),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
          child: const Text('Заблокировать'),
        ),
      ],
    ),
  );
}

void _showProductReportReasons(BuildContext context, ProductEntity product) {
  const reasons = [
    'Спам или дубли',
    'Запрещённый товар',
    'Обман или мошенничество',
    'Оскорбительное описание',
    'Другое',
  ];

  showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Text(
              'Причина жалобы',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ),
          const Divider(height: 1),
          ...reasons.map(
            (r) => ListTile(
              title: Text(r, style: TextStyle(color: Colors.red.shade700)),
              trailing: Icon(Icons.chevron_right, color: Colors.red.shade700),
              onTap: () {
                Navigator.pop(sheetCtx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Жалоба принята. Мы проверим объявление. Спасибо!',
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
