import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/supabase_constants.dart';
import '../../data/channel_owner_api.dart';
import '../../data/invite_candidates.dart';
import 'channel_invite_user_sheet.dart';

/// Результат создания канала из мастера.
class ChannelCreateResult {
  const ChannelCreateResult({
    required this.channelId,
    required this.title,
  });

  final String channelId;
  final String title;
}

/// Умное создание канала: название, описание, «плюшки», приглашения.
class ChannelCreateWizardSheet extends StatefulWidget {
  const ChannelCreateWizardSheet({
    super.key,
    required this.client,
    required this.ownerId,
  });

  final SupabaseClient client;
  final String ownerId;

  static Future<ChannelCreateResult?> show(
    BuildContext context, {
    required SupabaseClient client,
    required String ownerId,
  }) {
    return showModalBottomSheet<ChannelCreateResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: ChannelCreateWizardSheet(
          client: client,
          ownerId: ownerId,
        ),
      ),
    );
  }

  @override
  State<ChannelCreateWizardSheet> createState() =>
      _ChannelCreateWizardSheetState();
}

class _ChannelCreateWizardSheetState extends State<ChannelCreateWizardSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _signPosts = true;
  bool _showLinkPreview = true;
  bool _silentBroadcast = false;
  bool _loading = false;
  final Set<String> _inviteIds = {};

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickInvitees() async {
    final all = await loadInviteCandidates(widget.client, widget.ownerId);
    if (!mounted) return;
    final picked = await showChannelInviteUserPicker(
      context,
      candidates: all,
      initialSelection: Set<String>.from(_inviteIds),
      title: 'Кого пригласить в канал',
      confirmLabel: 'Готово',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _inviteIds
        ..clear()
        ..addAll(picked);
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    setState(() => _loading = true);
    try {
      final desc = _descriptionController.text.trim();
      final row = await widget.client
          .from(SupabaseConstants.userChannelsTable)
          .insert({
            'owner_id': widget.ownerId,
            'title': title,
            if (desc.isNotEmpty) 'description': desc,
            'sign_posts': _signPosts,
            'show_link_preview': _showLinkPreview,
            'silent_broadcast': _silentBroadcast,
          })
          .select('id')
          .single();
      final channelId = row['id'] as String;
      if (_inviteIds.isNotEmpty) {
        await ChannelOwnerApi.inviteUsers(
          widget.client,
          channelId: channelId,
          userIds: _inviteIds.toList(growable: false),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(
        ChannelCreateResult(channelId: channelId, title: title),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось создать канал: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottom),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.campaign_outlined, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Text(
                    'Новый канал',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Как в Telegram: канал в один поток, посты видят подписчики.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _titleController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Название канала',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Введите название';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                minLines: 2,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'О канале (необязательно)',
                  hintText: 'О чём канал, для кого подписчики',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Подпись к постам'),
                subtitle: const Text(
                  'Показывать название канала над текстом публикации',
                ),
                value: _signPosts,
                onChanged: (v) => setState(() => _signPosts = v),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Превью ссылок'),
                subtitle: const Text(
                  'Показывать расширенные ссылки в постах',
                ),
                value: _showLinkPreview,
                onChanged: (v) => setState(() => _showLinkPreview = v),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Тихий режим'),
                subtitle: const Text(
                  'Меньше навязчивых уведомлений подписчикам о новых постах',
                ),
                value: _silentBroadcast,
                onChanged: (v) => setState(() => _silentBroadcast = v),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _loading ? null : _pickInvitees,
                icon: const Icon(Icons.person_add_outlined),
                label: Text(
                  _inviteIds.isEmpty
                      ? 'Пригласить подписчиков'
                      : 'Приглашены: ${_inviteIds.length} — изменить',
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Создать канал'),
              ),
              TextButton(
                onPressed: _loading ? null : () => Navigator.of(context).pop(),
                child: const Text('Отмена'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
