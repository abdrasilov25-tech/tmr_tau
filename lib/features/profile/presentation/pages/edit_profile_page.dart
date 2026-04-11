import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import '../../../../core/router/go_router_pop_safe.dart';
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
  static const String _genderPrefsPrefix = 'tmr_tau_edit_profile_gender_';
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _bioController;
  late final TextEditingController _cityController;
  late final TextEditingController _residentNumberController;
  late final TextEditingController _instagramController;
  late final TextEditingController _telegramController;
  late final TextEditingController _websiteController;
  String? _gender; // 'male' / 'female' / null
  String? _currentUserId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final authState = context.read<AuthBloc>().state;
    final user = authState is AuthAuthenticated ? authState.user : null;
    _currentUserId = user?.id;
    _nameController = TextEditingController(text: user?.name ?? '');
    _usernameController = TextEditingController(text: user?.username ?? '');
    _bioController = TextEditingController(text: user?.bio ?? '');
    _cityController = TextEditingController();
    _residentNumberController = TextEditingController();
    _instagramController = TextEditingController();
    _telegramController = TextEditingController();
    _websiteController = TextEditingController();
    unawaited(_loadLocalGender());
    unawaited(_loadExtraFields());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    _cityController.dispose();
    _residentNumberController.dispose();
    _instagramController.dispose();
    _telegramController.dispose();
    _websiteController.dispose();
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
            city: _cityController.text.trim(),
            residentNumber: _residentNumberController.text.trim(),
            instagramUrl: _instagramController.text.trim(),
            telegramUsername: _telegramController.text.trim(),
            websiteUrl: _websiteController.text.trim(),
          );
      await _persistLocalGender(_gender);
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
      } catch (e) { debugPrint('$e'); }
      if (!mounted) return;
      // Обновим профиль в AuthBloc.
      context.read<AuthBloc>().add(const AuthCheckRequested());
      context.popOrGoHomeFeed();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить профиль: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _loadLocalGender() async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('$_genderPrefsPrefix$uid');
    if (!mounted) return;
    if (saved == 'male' || saved == 'female') {
      setState(() => _gender = saved);
    } else {
      setState(() => _gender = null);
    }
  }

  Future<void> _persistLocalGender(String? gender) async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final key = '$_genderPrefsPrefix$uid';
    if (gender == null || gender.isEmpty) {
      await prefs.remove(key);
      return;
    }
    await prefs.setString(key, gender);
  }

  Future<void> _loadExtraFields() async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) return;
    try {
      final row = await supa.Supabase.instance.client
          .from('users')
          .select('city,resident_number,instagram_url,telegram_username,website_url')
          .eq('id', uid)
          .maybeSingle();
      if (!mounted || row == null) return;
      _cityController.text = (row['city'] ?? '').toString();
      _residentNumberController.text = (row['resident_number'] ?? '').toString();
      _instagramController.text = (row['instagram_url'] ?? '').toString();
      _telegramController.text = (row['telegram_username'] ?? '').toString();
      _websiteController.text = (row['website_url'] ?? '').toString();
      setState(() {});
    } catch (e) { debugPrint('$e'); }
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
                const SizedBox(height: 16),
                TextFormField(
                  controller: _cityController,
                  decoration: const InputDecoration(
                    labelText: 'Город',
                    hintText: 'Например, Алматы',
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _residentNumberController,
                  decoration: const InputDecoration(
                    labelText: 'Номер жителя',
                    hintText: 'Городской номер (если есть)',
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _instagramController,
                  decoration: const InputDecoration(
                    labelText: 'Instagram',
                    hintText: 'https://instagram.com/username',
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _telegramController,
                  decoration: const InputDecoration(
                    labelText: 'Telegram',
                    hintText: '@username',
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _websiteController,
                  decoration: const InputDecoration(
                    labelText: 'Website',
                    hintText: 'https://your-site.com',
                  ),
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
                  onChanged: (v) {
                    setState(() => _gender = v);
                    unawaited(_persistLocalGender(v));
                  },
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        minLeadingWidth: 0,
                        horizontalTitleGap: 0,
                        leading: const Radio<String?>(value: 'male'),
                        title: const Text('Мужской'),
                        onTap: () {
                          setState(() => _gender = 'male');
                          unawaited(_persistLocalGender('male'));
                        },
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        minLeadingWidth: 0,
                        horizontalTitleGap: 0,
                        leading: const Radio<String?>(value: 'female'),
                        title: const Text('Женский'),
                        onTap: () {
                          setState(() => _gender = 'female');
                          unawaited(_persistLocalGender('female'));
                        },
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        minLeadingWidth: 0,
                        horizontalTitleGap: 0,
                        leading: const Radio<String?>(value: null),
                        title: const Text('Не указывать'),
                        onTap: () {
                          setState(() => _gender = null);
                          unawaited(_persistLocalGender(null));
                        },
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

