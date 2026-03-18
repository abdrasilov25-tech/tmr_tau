import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/accounts/account_manager.dart';
import '../../../../core/accounts/account_model.dart';
import '../../../../core/storage/local_reactions_storage.dart';
import '../../../../core/storage/multi_account_storage.dart';
import '../../../../core/theme/login_theme_presets.dart';
import '../../../../core/theme/themed_content_surface.dart';
import '../../../../core/theme/theme_decoration_helper.dart';
import '../../../../core/theme/theme_index_notifier.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../../core/widgets/theme_picker_sheet.dart';
import '../bloc/auth_bloc.dart';
import 'login_result.dart';

/// Цвета неоновой палитры
class _NeonColors {
  static const purple = Color(0xFF6B2D9E);
  static const pink = Color(0xFFE91E8C);
  static const orange = Color(0xFFFF6B35);
  static const yellow = Color(0xFFFFD23F);
  static const teal = Color(0xFF00D9D9);
  static const cyan = Color(0xFF00E5FF);
  static const white = Color(0xFFFFFFFF);
  static const white60 = Color(0x99FFFFFF);
  static const white40 = Color(0x66FFFFFF);
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.addAccountMode = false, this.initialEmail});

  /// Если true, после входа возвращаем LoginResult (для добавления аккаунта в переключатель).
  final bool addAccountMode;
  /// Подставить email (например при переключении аккаунта — остаётся ввести только пароль).
  final String? initialEmail;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _obscurePassword = true;
  bool _authHandled = false;
  List<AccountModel> _quickAccounts = const [];
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;
  late AnimationController _themeButtonScaleController;
  late Animation<double> _themeButtonScaleAnimation;
  late AnimationController _themeButtonGlowController;
  late Animation<double> _themeButtonGlowAnimation;
  bool _isPhoneLogin = false;
  bool _otpDialogOpen = false;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
    _themeButtonScaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _themeButtonScaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _themeButtonScaleController, curve: Curves.easeInOut),
    );
    _themeButtonGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _themeButtonGlowAnimation = Tween<double>(begin: 0.4, end: 0.8).animate(
      CurvedAnimation(parent: _themeButtonGlowController, curve: Curves.easeInOut),
    );
    _emailFocus.addListener(() => setState(() {}));
    _passwordFocus.addListener(() => setState(() {}));
    if (widget.initialEmail != null && widget.initialEmail!.isNotEmpty) {
      _emailController.text = widget.initialEmail!;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final manager = context.read<AccountManager>();
        manager.loadAccounts().then((accounts) {
          if (!mounted) return;
          if (accounts.isEmpty) return;
          // Удаляем дубликаты по userId: оставляем последний вариант.
          final byId = <String, AccountModel>{};
          for (final acc in accounts) {
            byId[acc.userId] = acc;
          }
          setState(() {
            _quickAccounts = byId.values.toList();
          });
        }).catchError((_) {});
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _scaleController.dispose();
    _themeButtonScaleController.dispose();
    _themeButtonGlowController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final contact = _emailController.text.trim();
    if (_isPhoneLogin) {
      context.read<AuthBloc>().add(AuthSignInWithSmsOtpRequested(phone: contact));
      return;
    }
    context.read<AuthBloc>().add(
      AuthSignInRequested(
        email: contact,
        password: _passwordController.text,
      ),
    );
  }

  void _showForgotPasswordDialog() {
    final initial = _emailController.text.trim();
    final dialogController = TextEditingController(
      text: initial.contains('@') ? initial : '',
    );

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Восстановить пароль'),
        content: TextField(
          controller: dialogController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            hintText: 'Email',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final email = dialogController.text.trim();
              if (email.isEmpty || !email.contains('@')) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Введите корректный email для восстановления.'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }
              context
                  .read<AuthBloc>()
                  .add(AuthResetPasswordRequested(email: email));
              Navigator.pop(ctx);
            },
            child: const Text('Восстановить'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _NeonColors.teal,
      body: Stack(
        fit: StackFit.expand,
        children: [
          ListenableBuilder(
            listenable: context.read<ThemeIndexNotifier>().listenable,
            builder: (context, _) {
              final notifier = context.read<ThemeIndexNotifier>();
              return Positioned.fill(
                child: Container(
                  decoration: themeDecoration(notifier.value, notifier.customImagePath),
                ),
              );
            },
          ),
          // Глубина: размытые светящиеся пятна
          _buildGlowSpots(),
          // Волнистые световые линии (неоновые волны)
          _buildNeonWaves(),
          // Контент поверх
          SafeArea(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                _buildScrollContent(),
                Positioned(
                  top: 8,
                  right: 16,
                  child: _buildThemeButton(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScrollContent() {
    return BlocConsumer<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthAuthenticated) {
          if (_authHandled) return;
          if (_otpDialogOpen) {
            // Если мы сейчас в режиме ввода SMS-кода, сначала закрываем диалог,
            // чтобы навигация не конфликтовала с dispose диалога.
            if (Navigator.of(context).canPop()) {
              _otpDialogOpen = false;
              Navigator.of(context).pop();
            } else {
              _otpDialogOpen = false;
            }
          }
          _authHandled = true;
          final password = _passwordController.text.trim();
          final passwordOrNull = password.isEmpty ? null : password;
          final storage = context.read<MultiAccountStorage>();
          final doNavigate = () {
            if (!context.mounted) return;
            if (widget.addAccountMode) {
              context.pop(LoginResult(
                userId: state.user.id,
                email: state.user.email,
                name: state.user.name,
                avatarUrl: state.user.avatarUrl,
                password: passwordOrNull,
              ));
            } else {
              context.go('/home/feed');
            }
          };
          if (passwordOrNull == null) {
            doNavigate();
            return;
          }
          storage.savePasswordImmediate(state.user.id, state.user.email, passwordOrNull);
          if (widget.addAccountMode) {
            doNavigate();
            return;
          }
          storage
              .addAccount(
                SavedAccount(
                  id: state.user.id,
                  email: state.user.email,
                  name: state.user.name,
                  avatarUrl: state.user.avatarUrl,
                ),
                password: passwordOrNull,
              )
              .then((_) => doNavigate())
              .catchError((_) => doNavigate());
          return;
        }
        if (state is AuthSmsOtpSent) {
          if (_otpDialogOpen) return;
          _otpDialogOpen = true;

          final phone = state.phone;
          showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) {
              final otpController = TextEditingController();
              return AlertDialog(
                title: const Text('Код из SMS'),
                content: TextField(
                  controller: otpController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: 'Введите код',
                    border: OutlineInputBorder(),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Отмена'),
                  ),
                  FilledButton(
                    onPressed: () {
                      final token = otpController.text.trim();
                      if (token.isEmpty || token.length < 4) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          const SnackBar(
                            content: Text('Введите код из SMS.'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                        return;
                      }
                      dialogContext.read<AuthBloc>().add(
                            AuthVerifySmsOtpRequested(
                              phone: phone,
                              token: token,
                            ),
                          );
                    },
                    child: const Text('Проверить'),
                  ),
                ],
              );
            },
          ).whenComplete(() {
            if (mounted) {
              _otpDialogOpen = false;
            }
          });
        }
        if (state is AuthError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: Colors.black87,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        if (state is AuthPasswordResetSent) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ссылка для восстановления отправлена на email.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      builder: (context, state) {
        final loading = state is AuthLoading;
        const titleColor = Color(0xFF1A1A1E);
        const subtitleColor = Color(0xFF5C5C66);
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 44),
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: ThemedContentSurface.loginPanel,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.06),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                Text(
                  'tmr_tau',
                  style: GoogleFonts.poppins(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: titleColor,
                    letterSpacing: 1.2,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Войдите в аккаунт',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    color: subtitleColor,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 26),
                _OAuthButton(
                  icon: Icons.apple_rounded,
                  label: 'Продолжить через Apple',
                  onPressed: loading
                      ? null
                      : () => context
                          .read<AuthBloc>()
                          .add(const AuthSignInWithAppleRequested()),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Expanded(
                      child: Divider(
                        color: Color(0xFFE6E7EC),
                        height: 1,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'или',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: subtitleColor,
                        ),
                      ),
                    ),
                    const Expanded(
                      child: Divider(
                        color: Color(0xFFE6E7EC),
                        height: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => setState(() => _isPhoneLogin = false),
                        child: Text(
                          'Email',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: _isPhoneLogin ? FontWeight.w500 : FontWeight.w700,
                            color: _isPhoneLogin ? subtitleColor : const Color(0xFF1A1A1E),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: () => setState(() => _isPhoneLogin = true),
                        child: Text(
                          'Телефон',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: _isPhoneLogin ? FontWeight.w700 : FontWeight.w500,
                            color: _isPhoneLogin ? const Color(0xFF1A1A1E) : subtitleColor,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _NeonTextField(
                  controller: _emailController,
                  focusNode: _emailFocus,
                  isFocused: _emailFocus.hasFocus,
                  hint: _isPhoneLogin ? 'Телефон' : 'Email',
                  keyboardType:
                      _isPhoneLogin ? TextInputType.phone : TextInputType.emailAddress,
                  borderColor: _isPhoneLogin ? _NeonColors.teal : _NeonColors.cyan,
                  lightSurface: true,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return _isPhoneLogin ? 'Введите телефон' : 'Введите email';
                    }
                    final value = v.trim();
                    if (_isPhoneLogin) {
                      final phoneRe = RegExp(r'^\+?[0-9]{7,15}$');
                      if (!phoneRe.hasMatch(value)) {
                        return 'Формат: +79990001122';
                      }
                      return null;
                    }
                    if (!value.contains('@')) return 'Некорректный email';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                if (!_isPhoneLogin) ...[
                  _NeonTextField(
                    controller: _passwordController,
                    focusNode: _passwordFocus,
                    isFocused: _passwordFocus.hasFocus,
                    hint: 'Пароль',
                    obscureText: _obscurePassword,
                    borderColor: _NeonColors.pink,
                    lightSurface: true,
                    toggleObscure: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Введите пароль' : null,
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: loading ? null : _showForgotPasswordDialog,
                      child: Text(
                        'Забыли пароль?',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF4B4BFF),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                _NeonLoginButton(
                  scaleAnimation: _scaleAnimation,
                  onTapDown: () => _scaleController.forward(),
                  onTapUp: () => _scaleController.reverse(),
                  onTapCancel: () => _scaleController.reverse(),
                  onPressed: loading ? null : _submit,
                  label: _isPhoneLogin ? 'Получить код' : 'Войти',
                  loading: loading,
                ),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () => context.push('/register'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.green,
                  ),
                  child: Text(
                    'Нет аккаунта? Зарегистрироваться',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.green,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                if (_quickAccounts.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Быстрый вход',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: subtitleColor,
                    ),
                    textAlign: TextAlign.left,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 76,
                    child: Builder(
                      builder: (context) {
                        final saved =
                            context.read<MultiAccountStorage>().getAccounts();
                        return ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _quickAccounts.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 12),
                          itemBuilder: (context, index) {
                            final acc = _quickAccounts[index];
                            final savedMatch = saved.firstWhere(
                              (s) =>
                                  s.id == acc.userId ||
                                  s.email.toLowerCase() ==
                                      acc.email.toLowerCase(),
                              orElse: () => SavedAccount(
                                id: acc.userId,
                                email: acc.email,
                              ),
                            );
                            final originalUrl = savedMatch.avatarUrl;
                            final uniqueUrl = (originalUrl != null &&
                                    originalUrl.isNotEmpty)
                                ? '$originalUrl?uid=${savedMatch.id}'
                                : null;
                            return GestureDetector(
                              onTap: loading
                                  ? null
                                  : () async {
                                      await _quickSwitchToAccount(acc);
                                    },
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CachedAvatar(
                                    imageUrl: uniqueUrl,
                                    radius: 18,
                                    fallbackText: savedMatch.displayName,
                                  ),
                                  const SizedBox(height: 4),
                                  SizedBox(
                                    width: 80,
                                    child: Text(
                                      savedMatch.displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.poppins(
                                        fontSize: 11,
                                        color: subtitleColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _quickSwitchToAccount(AccountModel account) async {
    try {
      final manager = context.read<AccountManager>();
      await manager.switchAccount(account);
      if (!mounted) return;
      context.read<AuthBloc>().add(const AuthCheckRequested());
      if (!mounted) return;
      context.go('/home/feed');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Не удалось войти в сохранённый аккаунт. Войдите заново.',
          ),
        ),
      );
      _emailController.text = account.email;
    }
  }

  Widget _buildThemeButton() {
    return AnimatedBuilder(
      animation: Listenable.merge([_themeButtonScaleAnimation, _themeButtonGlowAnimation]),
      builder: (context, child) {
        final glow = _themeButtonGlowAnimation.value;
        return Transform.scale(
          scale: _themeButtonScaleAnimation.value,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.12 * glow),
                  blurRadius: 12,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: child,
          ),
        );
      },
      child: GestureDetector(
        onTapDown: (_) => _themeButtonScaleController.forward(),
        onTapUp: (_) => _themeButtonScaleController.reverse(),
        onTapCancel: () => _themeButtonScaleController.reverse(),
        onTap: _showThemeBottomSheet,
        child: SizedBox(
          width: 38,
          height: 38,
          child: ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color.fromRGBO(255, 255, 255, 0.08),
                  border: Border.all(
                    color: const Color.fromRGBO(255, 255, 255, 0.15),
                    width: 1,
                  ),
                ),
                child: Icon(
                  Icons.palette_outlined,
                  size: 19,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showThemeBottomSheet() {
    final themeNotifier = context.read<ThemeIndexNotifier>();
    showThemePickerSheet(
      context,
      currentIndex: themeNotifier.value,
      onSelect: (index) => themeNotifier.setIndex(index),
      onAddCustom: () async {
        final picker = ImagePicker();
        final xFile = await picker.pickImage(source: ImageSource.gallery);
        if (xFile == null || !mounted) return;
        final bytes = await xFile.readAsBytes();
        if (!mounted) return;
        await themeNotifier.setCustomThemeFromImageBytes(bytes);
      },
    );
  }

  Widget _buildGlowSpots() {
    return Positioned.fill(
      child: CustomPaint(
        painter: _GlowSpotsPainter(),
      ),
    );
  }

  Widget _buildNeonWaves() {
    return Positioned.fill(
      child: CustomPaint(
        painter: _NeonWavesPainter(),
      ),
    );
  }
}

/// Bottom sheet: непрозрачная панель выбора темы — всё чётко видно
class _ThemeBottomSheet extends StatelessWidget {
  const _ThemeBottomSheet({
    required this.currentIndex,
    required this.onSelect,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;

  static final List<(String label, List<Color> colors)> _options = [
    ('Neon', LoginThemePresets.neon),
    ('Обычный', LoginThemePresets.ordinary),
    ('Синий градиент', LoginThemePresets.blue),
    ('Pink', LoginThemePresets.pink),
    ('Purple', LoginThemePresets.purple),
    ('Dark', LoginThemePresets.dark),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF252530),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF6B6B80),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Тема',
            style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Выберите фон экрана входа',
            style: GoogleFonts.poppins(
              fontSize: 15,
              color: Color(0xFFB0B0C0),
            ),
          ),
          const SizedBox(height: 24),
          ...List.generate(_options.length, (index) {
            final selected = index == currentIndex;
            final option = _options[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: selected ? const Color(0xFF3A3A4A) : const Color(0xFF2E2E3A),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  onTap: () => onSelect(index),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF6C9EFF)
                            : const Color(0xFF404055),
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: option.$2,
                            ),
                            border: Border.all(
                              color: const Color(0xFF505065),
                              width: 1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Text(
                            option.$1,
                            style: GoogleFonts.poppins(
                              fontSize: 17,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        if (selected)
                          const Icon(
                            Icons.check_circle_rounded,
                            color: Color(0xFF6C9EFF),
                            size: 26,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// Светящиеся размытые пятна для глубины
class _GlowSpotsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final spots = <({Offset offset, Color color})>[
      (offset: Offset(0.1 * size.width, 0.15 * size.height), color: const Color(0x406B2D9E)),
      (offset: Offset(0.85 * size.width, 0.3 * size.height), color: const Color(0x30E91E8C)),
      (offset: Offset(0.2 * size.width, 0.7 * size.height), color: const Color(0x25FF6B35)),
      (offset: Offset(0.9 * size.width, 0.8 * size.height), color: const Color(0x3000D9D9)),
      (offset: Offset(0.5 * size.width, 0.5 * size.height), color: const Color(0x15FFFFFF)),
    ];
    for (final spot in spots) {
      final paint = Paint()
        ..color = spot.color
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 100);
      canvas.drawCircle(spot.offset, 120, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Волнистые неоновые линии на фоне
class _NeonWavesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x18FFFFFF)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (var i = 0; i < 4; i++) {
      final path = Path();
      final yBase = 0.2 * size.height + i * 0.25 * size.height;
      path.moveTo(0, yBase);
      for (var x = 0.0; x <= size.width + 50; x += 20) {
        final t = x * 0.008 + i * 0.5;
        final y = yBase + 25 * (i.isEven ? 1 : -1) * _wave(t);
        if (x == 0) path.moveTo(x, y);
        path.lineTo(x, y);
      }
      canvas.drawPath(path, paint);
    }
  }

  double _wave(double t) {
    return math.sin(t);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Поле ввода в стиле glassmorphism с неоновой обводкой и glow при фокусе
class _NeonTextField extends StatelessWidget {
  const _NeonTextField({
    required this.controller,
    required this.focusNode,
    required this.isFocused,
    required this.hint,
    this.keyboardType,
    this.obscureText = false,
    this.borderColor = _NeonColors.cyan,
    this.toggleObscure,
    this.validator,
    this.lightSurface = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isFocused;
  final String hint;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Color borderColor;
  final VoidCallback? toggleObscure;
  final String? Function(String?)? validator;
  final bool lightSurface;

  static const _radius = 20.0;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: isFocused ? 1 : 0),
      duration: const Duration(milliseconds: 200),
      builder: (context, value, child) {
        final glowOpacity = lightSurface
            ? (0.08 + 0.12 * value)
            : (0.3 + 0.4 * value);
        final fillColor = lightSurface
            ? Colors.grey.shade50
            : Colors.white.withValues(alpha: 0.12);
        final hintColor =
            lightSurface ? Colors.grey.shade600 : _NeonColors.white40;
        final iconColor =
            lightSurface ? Colors.grey.shade700 : _NeonColors.white60;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_radius),
            boxShadow: [
              BoxShadow(
                color: borderColor.withValues(alpha: glowOpacity),
                blurRadius: isFocused ? 16 : 6,
                spreadRadius: isFocused ? 1 : 0,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_radius),
            child: lightSurface
                ? Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(_radius),
                      border: Border.all(
                        color: borderColor.withValues(
                            alpha: isFocused ? 0.85 : 0.45),
                        width: isFocused ? 2 : 1.5,
                      ),
                      color: fillColor,
                    ),
                    child: TextFormField(
                      controller: controller,
                      focusNode: focusNode,
                      keyboardType: keyboardType,
                      obscureText: obscureText,
                      validator: validator,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        color: Colors.black87,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        hintText: hint,
                        hintStyle: GoogleFonts.poppins(
                          color: hintColor,
                          fontSize: 15,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 18,
                        ),
                        border: InputBorder.none,
                        suffixIcon: toggleObscure != null
                            ? IconButton(
                                icon: Icon(
                                  obscureText
                                      ? Icons.visibility_off_rounded
                                      : Icons.visibility_rounded,
                                  color: iconColor,
                                  size: 22,
                                ),
                                onPressed: toggleObscure,
                              )
                            : null,
                      ),
                    ),
                  )
                : BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(_radius),
                        border: Border.all(
                          color: borderColor.withValues(
                              alpha: isFocused ? 0.9 : 0.5),
                          width: isFocused ? 2 : 1.5,
                        ),
                        color: fillColor,
                      ),
                      child: TextFormField(
                        controller: controller,
                        focusNode: focusNode,
                        keyboardType: keyboardType,
                        obscureText: obscureText,
                        validator: validator,
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          color: Colors.black,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          hintText: hint,
                          hintStyle: GoogleFonts.poppins(
                            color: hintColor,
                            fontSize: 15,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 18,
                          ),
                          border: InputBorder.none,
                          suffixIcon: toggleObscure != null
                              ? IconButton(
                                  icon: Icon(
                                    obscureText
                                        ? Icons.visibility_off_rounded
                                        : Icons.visibility_rounded,
                                    color: iconColor,
                                    size: 22,
                                  ),
                                  onPressed: toggleObscure,
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
          ),
        );
      },
    );
  }
}

/// Кнопка «Войти»: pill, градиент розовый→оранжевый, glow, scale при нажатии
class _NeonLoginButton extends StatelessWidget {
  const _NeonLoginButton({
    required this.scaleAnimation,
    required this.onTapDown,
    required this.onTapUp,
    required this.onTapCancel,
    required this.onPressed,
    this.label = 'Войти',
    required this.loading,
  });

  final Animation<double> scaleAnimation;
  final VoidCallback onTapDown;
  final VoidCallback onTapUp;
  final VoidCallback onTapCancel;
  final VoidCallback? onPressed;
  final String label;
  final bool loading;

  static const _radius = 32.0;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: scaleAnimation.value,
          child: child,
        );
      },
      child: GestureDetector(
        onTapDown: (_) => onTapDown(),
        onTapUp: (_) => onTapUp(),
        onTapCancel: onTapCancel,
        onTap: onPressed == null ? null : () => onPressed!(),
        child: Container(
          height: 58,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_radius),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                _NeonColors.pink,
                const Color(0xFFE85A4F),
                _NeonColors.orange,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
            boxShadow: [
              BoxShadow(
                color: _NeonColors.pink.withValues(alpha: 0.6),
                blurRadius: 24,
                spreadRadius: 0,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: _NeonColors.orange.withValues(alpha: 0.4),
                blurRadius: 16,
                spreadRadius: -2,
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(_radius),
              child: Center(
                child: loading
                    ? const SizedBox(
                        height: 26,
                        width: 26,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _NeonColors.white,
                          ),
                        ),
                      )
                    : Text(
                        label,
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: _NeonColors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Кнопка OAuth (Apple/Google) в стиле “современных” приложений.
class _OAuthButton extends StatelessWidget {
  const _OAuthButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.9),
          foregroundColor: Colors.black87,
          side: BorderSide(color: const Color(0xFFE6E7EC), width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}
