import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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

/// Цвета неоновой палитры
class _NeonColors {
  static const pink = Color(0xFFE91E8C);
  static const orange = Color(0xFFFF6B35);
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
    context.read<AuthBloc>().add(AuthSignInRequested(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        ));
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
          _authHandled = true;
          final password = _passwordController.text;
          final storage = context.read<MultiAccountStorage>();
          void doNavigate() {
            if (!context.mounted) return;
            if (widget.addAccountMode) {
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
          }
          if (password.isEmpty) {
            doNavigate();
            return;
          }
          storage.savePasswordImmediate(state.user.id, state.user.email, password);
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
      },
      builder: (context, state) {
        final loading = state is AuthLoading;
        final appleAvailable = !kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.iOS ||
                defaultTargetPlatform == TargetPlatform.macOS);
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
                const SizedBox(height: 36),
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
                const SizedBox(height: 20),
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
                const SizedBox(height: 40),
                _NeonLoginButton(
                  scaleAnimation: _scaleAnimation,
                  onTapDown: () => _scaleController.forward(),
                  onTapUp: () => _scaleController.reverse(),
                  onTapCancel: () => _scaleController.reverse(),
                  onPressed: loading ? null : _submit,
                  loading: loading,
                ),
                if (appleAvailable) ...[
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: loading
                        ? null
                        : () {
                            context
                                .read<AuthBloc>()
                                .add(const AuthSignInWithAppleRequested());
                          },
                    child: const Text('Продолжить с Apple'),
                  ),
                ],
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
                          separatorBuilder: (context, index) =>
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
    required this.loading,
  });

  final Animation<double> scaleAnimation;
  final VoidCallback onTapDown;
  final VoidCallback onTapUp;
  final VoidCallback onTapCancel;
  final VoidCallback? onPressed;
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
                        'Войти',
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
