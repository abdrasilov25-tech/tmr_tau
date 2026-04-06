import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/accounts/account_manager.dart';
import '../../../../core/accounts/account_model.dart';
import '../../../../core/storage/multi_account_storage.dart';
import '../../../../core/theme/themed_content_surface.dart';
import '../../../../core/theme/theme_decoration_helper.dart';
import '../../../../core/theme/theme_index_notifier.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../../core/widgets/theme_picker_sheet.dart';
import '../bloc/auth_bloc.dart';
import 'login_result.dart';

class _NeonColors {
  static const pink = Color(0xFFE91E8C);
  static const orange = Color(0xFFFF6B35);
  static const cyan = Color(0xFF00E5FF);
  static const white = Color(0xFFFFFFFF);
  static const white60 = Color(0x99FFFFFF);
  static const white40 = Color(0x66FFFFFF);
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.addAccountMode = false, this.initialEmail});

  final bool addAccountMode;
  final String? initialEmail;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _obscurePassword = true;
  bool _googleInProgress = false;
  bool _appleInProgress = false;
  bool _authHandled = false;
  List<AccountModel> _quickAccounts = const [];

  // Scale for main login button
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  // Theme button
  late AnimationController _themeButtonScaleController;
  late Animation<double> _themeButtonScaleAnimation;
  late AnimationController _themeButtonGlowController;
  late Animation<double> _themeButtonGlowAnimation;

  // Staggered entrance
  late AnimationController _entranceController;
  late Animation<double> _logoScale;
  late Animation<double> _logoFade;
  late Animation<Offset> _panelSlide;
  late Animation<double> _panelFade;

  // Floating particles
  late AnimationController _particlesController;

  // Shimmer on login button
  late AnimationController _shimmerController;
  late Animation<double> _shimmerAnimation;

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
    _themeButtonScaleAnimation =
        Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(
          parent: _themeButtonScaleController, curve: Curves.easeInOut),
    );
    _themeButtonGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _themeButtonGlowAnimation =
        Tween<double>(begin: 0.4, end: 0.8).animate(
      CurvedAnimation(
          parent: _themeButtonGlowController, curve: Curves.easeInOut),
    );

    // Entrance: logo fades in first, then panel slides up
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _logoScale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.45, curve: Curves.easeOutBack),
      ),
    );
    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.35, curve: Curves.easeOut),
      ),
    );
    _panelSlide =
        Tween<Offset>(begin: const Offset(0, 0.10), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.25, 0.85, curve: Curves.easeOutCubic),
      ),
    );
    _panelFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.25, 0.75, curve: Curves.easeOut),
      ),
    );

    // Particles loop
    _particlesController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    // Shimmer loop
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
    _shimmerAnimation =
        Tween<double>(begin: -1.5, end: 2.5).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.easeInOut),
    );

    _emailFocus.addListener(() => setState(() {}));
    _passwordFocus.addListener(() => setState(() {}));

    if (widget.initialEmail != null && widget.initialEmail!.isNotEmpty) {
      _emailController.text = widget.initialEmail!;
    }

    _entranceController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final manager = context.read<AccountManager>();
        manager.loadAccounts().then((accounts) {
          if (!mounted) return;
          if (accounts.isEmpty) return;
          final byId = <String, AccountModel>{};
          for (final acc in accounts) {
            byId[acc.userId] = acc;
          }
          setState(() => _quickAccounts = byId.values.toList());
        }).catchError((_) {});
      } catch (e) { debugPrint('$e'); }
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
    _entranceController.dispose();
    _particlesController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    context.read<AuthBloc>().add(AuthSignInRequested(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Theme background
          ListenableBuilder(
            listenable: context.read<ThemeIndexNotifier>().listenable,
            builder: (context, _) {
              final notifier = context.read<ThemeIndexNotifier>();
              return Positioned.fill(
                child: Container(
                  decoration: themeDecoration(
                      notifier.value, notifier.customImagePath),
                ),
              );
            },
          ),
          ColoredBox(color: Colors.black.withValues(alpha: 0.45)),
          // Static glow spots
          _buildGlowSpots(),
          // Animated floating particles
          AnimatedBuilder(
            animation: _particlesController,
            builder: (context, _) => Positioned.fill(
              child: CustomPaint(
                painter: _ParticlesPainter(_particlesController.value),
              ),
            ),
          ),
          // Neon waves
          _buildNeonWaves(),
          // Main content
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
        if (state is AuthOAuthDismissed) {
          if (_googleInProgress || _appleInProgress) {
            setState(() {
              _googleInProgress = false;
              _appleInProgress = false;
            });
          }
          return;
        }
        if (state is! AuthLoading) {
          if (_googleInProgress || _appleInProgress) {
            setState(() {
              _googleInProgress = false;
              _appleInProgress = false;
            });
          }
        }
        if (state is AuthAuthenticated) {
          if (_authHandled) return;
          _authHandled = true;
          final password = _passwordController.text;
          final storage = context.read<MultiAccountStorage>();
          void doNavigate() {
            if (!context.mounted) return;
            if (widget.addAccountMode) {
              if (context.canPop()) {
                context.pop(LoginResult(
                  userId: state.user.id,
                  email: state.user.email,
                  name: state.user.name,
                  avatarUrl: state.user.avatarUrl,
                  password: password,
                ));
              } else {
                context.go('/home/feed');
              }
            } else {
              context.go('/home/feed');
            }
          }

          if (password.isEmpty) {
            doNavigate();
            return;
          }
          storage.savePasswordImmediate(
              state.user.id, state.user.email, password);
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
                password: password,
              )
              .then((_) => doNavigate())
              .catchError((_) => doNavigate());
          return;
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
              content: Text('Ссылка для сброса отправлена на почту'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      builder: (context, state) {
        final loading = state is AuthLoading;
        final oauthLoading = _googleInProgress || _appleInProgress;
        final googleLoading = _googleInProgress;
        final appleLoading = _appleInProgress;
        final appleAvailable = !kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.iOS ||
                defaultTargetPlatform == TargetPlatform.macOS);

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 28),
                // Animated logo section
                AnimatedBuilder(
                  animation: Listenable.merge([_logoScale, _logoFade]),
                  builder: (_, child) => Opacity(
                    opacity: _logoFade.value,
                    child: Transform.scale(
                      scale: _logoScale.value,
                      child: child,
                    ),
                  ),
                  child: _buildAppLogo(),
                ),
                const SizedBox(height: 28),
                // Animated main panel
                SlideTransition(
                  position: _panelSlide,
                  child: FadeTransition(
                    opacity: _panelFade,
                    child: _buildMainPanel(
                      loading: loading,
                      oauthLoading: oauthLoading,
                      googleLoading: googleLoading,
                      appleLoading: appleLoading,
                      appleAvailable: appleAvailable,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAppLogo() {
    return Column(
      children: [
        // Glowing icon container
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFE91E8C), Color(0xFFFF6B35)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE91E8C).withValues(alpha: 0.55),
                blurRadius: 36,
                spreadRadius: 4,
              ),
              BoxShadow(
                color: const Color(0xFFFF6B35).withValues(alpha: 0.3),
                blurRadius: 20,
                spreadRadius: -4,
              ),
            ],
          ),
          child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 46),
        ),
        const SizedBox(height: 18),
        Text(
          'TMR TAU',
          style: GoogleFonts.poppins(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: 5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Войдите в свой аккаунт',
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: Colors.white.withValues(alpha: 0.55),
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }

  Widget _buildMainPanel({
    required bool loading,
    required bool oauthLoading,
    required bool googleLoading,
    required bool appleLoading,
    required bool appleAvailable,
  }) {
    const subtitleColor = Color(0xFF5C5C66);

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            color: ThemedContentSurface.loginPanel,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.14),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 48,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Social buttons first (like Airbnb, Spotify, etc.) ──
                if (appleAvailable) ...[
                  _SocialAuthButton(
                    onPressed: loading || oauthLoading
                        ? null
                        : () {
                            setState(() {
                              _appleInProgress = true;
                              _googleInProgress = false;
                            });
                            context
                                .read<AuthBloc>()
                                .add(const AuthSignInWithAppleRequested());
                          },
                    loading: appleLoading,
                    backgroundColor: const Color(0xFF111111),
                    textColor: Colors.white,
                    borderColor: Colors.white.withValues(alpha: 0.12),
                    icon: const FaIcon(
                      FontAwesomeIcons.apple,
                      size: 21,
                      color: Colors.white,
                    ),
                    label: 'Продолжить с Apple',
                  ),
                  const SizedBox(height: 12),
                ],
                _SocialAuthButton(
                  onPressed: loading || oauthLoading
                      ? null
                      : () {
                          setState(() {
                            _googleInProgress = true;
                            _appleInProgress = false;
                          });
                          context
                              .read<AuthBloc>()
                              .add(const AuthSignInWithGoogleRequested());
                        },
                  loading: googleLoading,
                  backgroundColor: Colors.white,
                  textColor: const Color(0xFF3C4043),
                  borderColor: const Color(0xFFE8EAED),
                  icon: const _GoogleLogo(size: 20),
                  label: 'Продолжить с Google',
                ),
                const SizedBox(height: 24),
                // ── Divider "или" ──
                const _OrDivider(),
                const SizedBox(height: 20),
                // ── Email & password ──
                _NeonTextField(
                  controller: _emailController,
                  focusNode: _emailFocus,
                  isFocused: _emailFocus.hasFocus,
                  hint: 'Email',
                  keyboardType: TextInputType.emailAddress,
                  borderColor: _NeonColors.cyan,
                  lightSurface: true,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Введите email';
                    if (!v.contains('@')) return 'Некорректный email';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
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
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: loading || oauthLoading
                        ? null
                        : () {
                            final email = _emailController.text.trim();
                            if (email.isEmpty || !email.contains('@')) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Введите корректный email для сброса пароля'),
                                ),
                              );
                              return;
                            }
                            context.read<AuthBloc>().add(
                                  AuthResetPasswordRequested(email: email),
                                );
                          },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Забыли пароль?',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: _NeonColors.pink,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                // ── Main login button with shimmer ──
                _NeonLoginButton(
                  scaleAnimation: _scaleAnimation,
                  shimmerAnimation: _shimmerAnimation,
                  onTapDown: () => _scaleController.forward(),
                  onTapUp: () => _scaleController.reverse(),
                  onTapCancel: () => _scaleController.reverse(),
                  onPressed: loading || oauthLoading ? null : _submit,
                  loading: loading,
                ),
                const SizedBox(height: 22),
                // ── Register link ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Нет аккаунта? ',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: subtitleColor,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => context.push('/register'),
                      child: Text(
                        'Зарегистрироваться',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: _NeonColors.pink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                // ── Quick accounts ──
                if (_quickAccounts.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  Text(
                    'Быстрый вход',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: subtitleColor,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 76,
                    child: Builder(
                      builder: (context) {
                        final saved =
                            context.read<MultiAccountStorage>().getAccounts();
                        return ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _quickAccounts.length,
                          separatorBuilder: (context, _) =>
                              const SizedBox(width: 12),
                          itemBuilder: (context, index) {
                            final acc = _quickAccounts[index];
                            final savedMatch = saved.firstWhere(
                              (s) =>
                                  s.id == acc.userId ||
                                  s.email.toLowerCase() ==
                                      acc.email.toLowerCase(),
                              orElse: () => SavedAccount(
                                  id: acc.userId, email: acc.email),
                            );
                            final originalUrl = savedMatch.avatarUrl;
                            final uniqueUrl =
                                (originalUrl != null && originalUrl.isNotEmpty)
                                    ? '$originalUrl?uid=${savedMatch.id}'
                                    : null;
                            return GestureDetector(
                              onTap: loading
                                  ? null
                                  : () async =>
                                      _quickSwitchToAccount(acc),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: _NeonColors.pink
                                            .withValues(alpha: 0.45),
                                        width: 2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: _NeonColors.pink
                                              .withValues(alpha: 0.2),
                                          blurRadius: 8,
                                        ),
                                      ],
                                    ),
                                    child: CachedAvatar(
                                      imageUrl: uniqueUrl,
                                      radius: 20,
                                      fallbackText: savedMatch.displayName,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  SizedBox(
                                    width: 74,
                                    child: Text(
                                      savedMatch.displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.poppins(
                                        fontSize: 10,
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
                ],
              ],
            ),
          ),
        ),
      ),
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Не удалось войти в сохранённый аккаунт. Войдите заново.'),
        ),
      );
      _emailController.text = account.email;
    }
  }

  Widget _buildThemeButton() {
    return AnimatedBuilder(
      animation:
          Listenable.merge([_themeButtonScaleAnimation, _themeButtonGlowAnimation]),
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
        try {
          final picker = ImagePicker();
          final xFile = await picker.pickImage(source: ImageSource.gallery);
          if (xFile == null || !mounted) return;
          final bytes = await xFile.readAsBytes();
          if (!mounted) return;
          await themeNotifier.setCustomThemeFromImageBytes(bytes);
        } on PlatformException catch (e, st) {
          debugPrint('LoginPage custom theme pick: $e\n$st');
          if (!mounted) return;
          final msg = (e.message ?? '').toLowerCase();
          final denied = e.code == 'photo_access_denied' ||
              e.code == 'camera_access_denied' ||
              msg.contains('permission') ||
              msg.contains('denied');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                denied
                    ? 'Нет доступа к фото. Разрешите доступ в настройках устройства.'
                    : 'Не удалось выбрать изображение.',
              ),
            ),
          );
        } catch (e, st) {
          debugPrint('LoginPage custom theme pick: $e\n$st');
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Не удалось выбрать изображение для темы.'),
            ),
          );
        }
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

// ─────────────────────────────────────────────
// Social auth button (Apple / Google style)
// ─────────────────────────────────────────────

class _SocialAuthButton extends StatefulWidget {
  const _SocialAuthButton({
    required this.onPressed,
    required this.loading,
    required this.backgroundColor,
    required this.textColor,
    required this.borderColor,
    required this.icon,
    required this.label,
  });

  final VoidCallback? onPressed;
  final bool loading;
  final Color backgroundColor;
  final Color textColor;
  final Color borderColor;
  final Widget icon;
  final String label;

  @override
  State<_SocialAuthButton> createState() => _SocialAuthButtonState();
}

class _SocialAuthButtonState extends State<_SocialAuthButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onPressed?.call();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: widget.backgroundColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: widget.borderColor, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: widget.loading
              ? Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(widget.textColor),
                    ),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    widget.icon,
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        widget.label,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: widget.textColor,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Google 4-color "G" logo (CustomPaint)
// ─────────────────────────────────────────────

class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;
    final r = w * 0.46;
    final stroke = w * 0.175;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt
      ..isAntiAlias = true;

    final rect = Rect.fromCircle(
        center: Offset(cx, cy), radius: r - stroke / 2);

    // Red arc  (top-right → right gap)  ~315° → 60°  (= -45° → 60°)
    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(
        rect, _deg(-45), _deg(105), false, paint);

    // Yellow arc  60° → 120°
    paint.color = const Color(0xFFFBBC05);
    canvas.drawArc(rect, _deg(60), _deg(60), false, paint);

    // Green arc  120° → 240°
    paint.color = const Color(0xFF34A853);
    canvas.drawArc(rect, _deg(120), _deg(120), false, paint);

    // Blue arc  240° → 315°
    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(rect, _deg(240), _deg(75), false, paint);

    // Horizontal bar (the tongue of the G)
    final barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final barTop = cy - stroke / 2;
    final barBottom = cy + stroke / 2;
    final barLeft = cx; // starts from center
    final barRight = cx + r - stroke / 2 + stroke * 0.05;

    final barPath = Path()
      ..addRRect(RRect.fromRectAndCorners(
        Rect.fromLTRB(barLeft, barTop, barRight, barBottom),
        topRight: const Radius.circular(4),
        bottomRight: const Radius.circular(4),
      ));
    canvas.drawPath(barPath, barPaint);
  }

  static double _deg(double degrees) => degrees * math.pi / 180;

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────
// "— или —" divider
// ─────────────────────────────────────────────

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  Colors.grey.shade300,
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'или',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: const Color(0xFFAAAAAA),
              letterSpacing: 0.5,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.grey.shade300,
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Neon text field (glassmorphism + glow)
// ─────────────────────────────────────────────

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
        final glowOpacity =
            lightSurface ? (0.08 + 0.12 * value) : (0.3 + 0.4 * value);
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
                blurRadius: isFocused ? 18 : 6,
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
                        color: borderColor
                            .withValues(alpha: isFocused ? 0.85 : 0.45),
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
                          color: borderColor
                              .withValues(alpha: isFocused ? 0.9 : 0.5),
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

// ─────────────────────────────────────────────
// Main "Войти" button with shimmer sweep
// ─────────────────────────────────────────────

class _NeonLoginButton extends StatelessWidget {
  const _NeonLoginButton({
    required this.scaleAnimation,
    required this.shimmerAnimation,
    required this.onTapDown,
    required this.onTapUp,
    required this.onTapCancel,
    required this.onPressed,
    required this.loading,
  });

  final Animation<double> scaleAnimation;
  final Animation<double> shimmerAnimation;
  final VoidCallback onTapDown;
  final VoidCallback onTapUp;
  final VoidCallback onTapCancel;
  final VoidCallback? onPressed;
  final bool loading;

  static const _radius = 32.0;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([scaleAnimation, shimmerAnimation]),
      builder: (context, child) {
        return Transform.scale(
          scale: scaleAnimation.value,
          child: GestureDetector(
            onTapDown: (_) => onTapDown(),
            onTapUp: (_) => onTapUp(),
            onTapCancel: onTapCancel,
            child: Container(
              height: 58,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_radius),
                gradient: const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Color(0xFFE91E8C),
                    Color(0xFFE85A4F),
                    Color(0xFFFF6B35),
                  ],
                  stops: [0.0, 0.5, 1.0],
                ),
                boxShadow: [
                  BoxShadow(
                    color: _NeonColors.pink.withValues(alpha: 0.55),
                    blurRadius: 28,
                    spreadRadius: 0,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: _NeonColors.orange.withValues(alpha: 0.35),
                    blurRadius: 16,
                    spreadRadius: -4,
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Shimmer sweep overlay
                  if (!loading)
                    Positioned.fill(
                      child: LayoutBuilder(builder: (_, constraints) {
                        final w = constraints.maxWidth;
                        final sweep = shimmerAnimation.value;
                        return CustomPaint(
                          painter: _ShimmerPainter(
                            progress: sweep,
                            width: w,
                          ),
                        );
                      }),
                    ),
                  Material(
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
                                      _NeonColors.white),
                                ),
                              )
                            : Text(
                                'Войти',
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: _NeonColors.white,
                                  letterSpacing: 0.5,
                                ),
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
    );
  }
}

// ─────────────────────────────────────────────
// Shimmer sweep painter
// ─────────────────────────────────────────────

class _ShimmerPainter extends CustomPainter {
  const _ShimmerPainter({required this.progress, required this.width});
  final double progress;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final shimmerWidth = size.width * 0.4;
    final x = progress * (size.width + shimmerWidth) - shimmerWidth;

    final gradient = LinearGradient(
      colors: [
        Colors.white.withValues(alpha: 0.0),
        Colors.white.withValues(alpha: 0.18),
        Colors.white.withValues(alpha: 0.0),
      ],
      stops: const [0.0, 0.5, 1.0],
    );

    final paint = Paint()
      ..shader = gradient.createShader(
        Rect.fromLTWH(x, 0, shimmerWidth, size.height),
      );

    canvas.drawRect(
      Rect.fromLTWH(x, 0, shimmerWidth, size.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ShimmerPainter old) =>
      old.progress != progress;
}

// ─────────────────────────────────────────────
// Floating particles painter
// ─────────────────────────────────────────────

class _ParticlesPainter extends CustomPainter {
  _ParticlesPainter(this.t);
  final double t;

  static final _rand = math.Random(42);
  static final List<_Particle> _particles = List.generate(28, (i) {
    return _Particle(
      x: _rand.nextDouble(),
      y: _rand.nextDouble(),
      radius: 1.2 + _rand.nextDouble() * 2.0,
      speed: 0.04 + _rand.nextDouble() * 0.08,
      phase: _rand.nextDouble() * math.pi * 2,
      opacity: 0.15 + _rand.nextDouble() * 0.35,
    );
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in _particles) {
      final yProgress = (p.y + p.speed * t) % 1.0;
      final xWave = p.x + 0.04 * math.sin(t * math.pi * 2 + p.phase);
      final px = xWave * size.width;
      final py = (1.0 - yProgress) * size.height;

      final paint = Paint()
        ..color = Colors.white.withValues(alpha: p.opacity * (1 - yProgress * 0.5))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.radius * 0.8);

      canvas.drawCircle(Offset(px, py), p.radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlesPainter old) => old.t != t;
}

class _Particle {
  const _Particle({
    required this.x,
    required this.y,
    required this.radius,
    required this.speed,
    required this.phase,
    required this.opacity,
  });
  final double x;
  final double y;
  final double radius;
  final double speed;
  final double phase;
  final double opacity;
}

// ─────────────────────────────────────────────
// Background painters (unchanged)
// ─────────────────────────────────────────────

class _GlowSpotsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final spots = <({Offset offset, Color color})>[
      (
        offset: Offset(0.1 * size.width, 0.15 * size.height),
        color: const Color(0x406B2D9E)
      ),
      (
        offset: Offset(0.85 * size.width, 0.3 * size.height),
        color: const Color(0x30E91E8C)
      ),
      (
        offset: Offset(0.2 * size.width, 0.7 * size.height),
        color: const Color(0x25FF6B35)
      ),
      (
        offset: Offset(0.9 * size.width, 0.8 * size.height),
        color: const Color(0x3000D9D9)
      ),
      (
        offset: Offset(0.5 * size.width, 0.5 * size.height),
        color: const Color(0x15FFFFFF)
      ),
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

class _NeonWavesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x12FFFFFF)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (var i = 0; i < 4; i++) {
      final path = Path();
      final yBase = 0.2 * size.height + i * 0.25 * size.height;
      path.moveTo(0, yBase);
      for (var x = 0.0; x <= size.width + 50; x += 20) {
        final tVal = x * 0.008 + i * 0.5;
        final y = yBase + 25 * (i.isEven ? 1 : -1) * math.sin(tVal);
        if (x == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
