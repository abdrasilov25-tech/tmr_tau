import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/storage/multi_account_storage.dart';
import '../../../../core/theme/themed_content_surface.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/repositories/profile_repository.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _bioController;
  String? _gender; // 'male' / 'female' / null
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final authState = context.read<AuthBloc>().state;
    final user = authState is AuthAuthenticated ? authState.user : null;
    _nameController = TextEditingController(text: user?.name ?? '');
    _usernameController = TextEditingController(text: user?.username ?? '');
    _bioController = TextEditingController(text: user?.bio ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;
    final user = authState.user;
    setState(() => _saving = true);
    try {
      final newName = _nameController.text.trim().isEmpty
          ? null
          : _nameController.text.trim();
      await context.read<ProfileRepository>().updateProfile(
            userId: user.id,
            name: newName,
            bio: _bioController.text.trim().isEmpty
                ? null
                : _bioController.text.trim(),
            username: _usernameController.text.trim().isEmpty
                ? null
                : _usernameController.text.trim(),
            gender: _gender,
          );
      if (!mounted) return;
      // Обновим локальное имя в сохранённых аккаунтах (для свитчера и быстрого входа).
      try {
        final storage = context.read<MultiAccountStorage>();
        await storage.addAccount(
          SavedAccount(
            id: user.id,
            email: user.email,
            name: newName ?? user.name,
            avatarUrl: user.avatarUrl,
          ),
        );
      } catch (_) {}
      // Обновим профиль в AuthBloc.
      context.read<AuthBloc>().add(const AuthCheckRequested());
      context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить профиль: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Редактировать профиль'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: DecoratedBox(
            decoration: ThemedContentSurface.profileCardDecoration(),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Имя',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Введите имя' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Имя пользователя',
                    hintText: 'username',
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _bioController,
                  decoration: const InputDecoration(
                    labelText: 'О себе',
                    alignLabelWithHint: true,
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 24),
                Text(
                  'Пол',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: ThemedContentSurface.profileTextPrimary,
                      ),
                ),
                RadioGroup<String?>(
                  groupValue: _gender,
                  onChanged: (v) => setState(() => _gender = v),
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        minLeadingWidth: 0,
                        horizontalTitleGap: 0,
                        leading: const Radio<String?>(value: 'male'),
                        title: const Text('Мужской'),
                        onTap: () => setState(() => _gender = 'male'),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        minLeadingWidth: 0,
                        horizontalTitleGap: 0,
                        leading: const Radio<String?>(value: 'female'),
                        title: const Text('Женский'),
                        onTap: () => setState(() => _gender = 'female'),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        minLeadingWidth: 0,
                        horizontalTitleGap: 0,
                        leading: const Radio<String?>(value: null),
                        title: const Text('Не указывать'),
                        onTap: () => setState(() => _gender = null),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Сохранить'),
                ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

