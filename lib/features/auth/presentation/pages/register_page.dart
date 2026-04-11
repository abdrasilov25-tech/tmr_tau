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

import '../../../../core/router/go_router_pop_safe.dart';
import '../../../../core/theme/theme_decoration_helper.dart';
import '../../../../core/theme/theme_index_notifier.dart';
import '../../../../core/widgets/theme_picker_sheet.dart';
import '../bloc/auth_bloc.dart';

// ─── Color palette (matches LoginPage) ───────────────────────────────────────
class _C {
  static const green  = Color(0xFF00E5A0);
  static const cyan   = Color(0xFF00E5FF);
  static const pink   = Color(0xFFE91E8C);
  static const orange = Color(0xFFFF6B35);
  static const white  = Color(0xFFFFFFFF);
  static const w60    = Color(0x99FFFFFF);
  static const w40    = Color(0x66FFFFFF);
  static const w15    = Color(0x26FFFFFF);
  static const w08    = Color(0x14FFFFFF);
  /// Текст и иконки внутри светлых полей ввода.
  static const fieldText = Color(0xFF111827);
  static const fieldHint = Color(0xFF6B7280);
  static const fieldLabelMuted = Color(0xFF4B5563);
  /// Фон поля (непрозрачный, чтобы текст не сливался с градиентом экрана).
  static const fieldFill = Color(0xFFF9FAFB);
  static const fieldFillFocused = Color(0xFFFFFFFF);
}

// ─────────────────────────────────────────────────────────────────────────────

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage>
    with TickerProviderStateMixin {

  // Step 0: name  |  Step 1: email + password
  int _step = 0;

  final _nameController    = TextEditingController();
  final _residentNumberController = TextEditingController();
  final _emailController   = TextEditingController();
  final _passwordController   = TextEditingController();
  final _confirmController    = TextEditingController();

  final _nameFocus    = FocusNode();
  final _residentFocus = FocusNode();
  final _emailFocus   = FocusNode();
  final _passwordFocus   = FocusNode();
  final _confirmFocus    = FocusNode();

  bool _obscurePassword = true;
  bool _obscureConfirm  = true;
  bool _googleInProgress = false;
  bool _appleInProgress  = false;
  bool _authHandled = false;

  // Field error messages
  String? _nameError;
  String? _emailError;
  String? _passwordError;
  String? _confirmError;

  // Animations
  late AnimationController _entranceCtrl;
  late Animation<double>   _panelFade;
  late Animation<Offset>   _panelSlide;
  late Animation<double>   _logoFade;
  late Animation<double>   _logoScale;

  late AnimationController _particlesCtrl;

  late AnimationController _shimmerCtrl;
  late Animation<double>   _shimmerAnim;

  late AnimationController _btnScaleCtrl;
  late Animation<double>   _btnScale;

  late AnimationController _themeScaleCtrl;
  late Animation<double>   _themeScale;
  late AnimationController _themeGlowCtrl;
  late Animation<double>   _themeGlow;

  @override
  void initState() {
    super.initState();

    _entranceCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100),
    );
    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entranceCtrl,
          curve: const Interval(0.0, 0.35, curve: Curves.easeOut)));
    _logoScale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _entranceCtrl,
          curve: const Interval(0.0, 0.45, curve: Curves.easeOutBack)));
    _panelSlide =
        Tween<Offset>(begin: const Offset(0, 0.10), end: Offset.zero).animate(
      CurvedAnimation(parent: _entranceCtrl,
          curve: const Interval(0.25, 0.85, curve: Curves.easeOutCubic)));
    _panelFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entranceCtrl,
          curve: const Interval(0.25, 0.75, curve: Curves.easeOut)));

    _particlesCtrl = AnimationController(
      vsync: this, duration: const Duration(seconds: 10),
    )..repeat();

    _shimmerCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2800),
    )..repeat();
    _shimmerAnim = Tween<double>(begin: -1.5, end: 2.5).animate(
      CurvedAnimation(parent: _shimmerCtrl, curve: Curves.easeInOut));

    _btnScaleCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 100),
    );
    _btnScale = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _btnScaleCtrl, curve: Curves.easeInOut));

    _themeScaleCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 120),
    );
    _themeScale = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _themeScaleCtrl, curve: Curves.easeInOut));
    _themeGlowCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _themeGlow = Tween<double>(begin: 0.4, end: 0.8).animate(
      CurvedAnimation(parent: _themeGlowCtrl, curve: Curves.easeInOut));

    for (final fn in [
      _nameFocus,
      _residentFocus,
      _emailFocus,
      _passwordFocus,
      _confirmFocus,
    ]) {
      fn.addListener(() => setState(() {}));
    }

    _entranceCtrl.forward();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _residentNumberController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _nameFocus.dispose();
    _residentFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    _entranceCtrl.dispose();
    _particlesCtrl.dispose();
    _shimmerCtrl.dispose();
    _btnScaleCtrl.dispose();
    _themeScaleCtrl.dispose();
    _themeGlowCtrl.dispose();
    super.dispose();
  }

  // ─── Validation ───────────────────────────────────────────────────────────

  bool _validateStep0() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Введите имя');
      return false;
    }
    if (name.length < 2) {
      setState(() => _nameError = 'Имя слишком короткое');
      return false;
    }
    setState(() => _nameError = null);
    return true;
  }

  bool _validateStep1() {
    bool ok = true;
    final email = _emailController.text.trim();
    final pass  = _passwordController.text;
    final conf  = _confirmController.text;

    if (email.isEmpty) {
      _emailError = 'Введите email';
      ok = false;
    } else if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(email)) {
      _emailError = 'Некорректный email';
      ok = false;
    } else {
      _emailError = null;
    }

    if (pass.isEmpty) {
      _passwordError = 'Введите пароль';
      ok = false;
    } else if (pass.length < 6) {
      _passwordError = 'Минимум 6 символов';
      ok = false;
    } else {
      _passwordError = null;
    }

    if (conf.isEmpty) {
      _confirmError = 'Повторите пароль';
      ok = false;
    } else if (conf != pass) {
      _confirmError = 'Пароли не совпадают';
      ok = false;
    } else {
      _confirmError = null;
    }

    setState(() {});
    return ok;
  }

  void _nextStep() {
    if (_step == 0) {
      if (!_validateStep0()) return;
      setState(() => _step = 1);
    } else {
      _submit();
    }
  }

  void _submit() {
    if (!_validateStep1()) return;
    final auth = context.read<AuthBloc>().state;
    if (auth is AuthLoading) return;
    final rn = _residentNumberController.text.trim();
    context.read<AuthBloc>().add(AuthSignUpRequested(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      name: _nameController.text.trim(),
      residentNumber: rn.isEmpty ? null : rn,
    ));
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Theme gradient background
          ListenableBuilder(
            listenable: context.read<ThemeIndexNotifier>().listenable,
            builder: (context, _) {
              final n = context.read<ThemeIndexNotifier>();
              return Positioned.fill(
                child: Container(
                  decoration: themeDecoration(n.value, n.customImagePath),
                ),
              );
            },
          ),
          ColoredBox(color: Colors.black.withValues(alpha: 0.45)),
          _buildGlowSpots(),
          AnimatedBuilder(
            animation: _particlesCtrl,
            builder: (_, __) => Positioned.fill(
              child: CustomPaint(
                painter: _ParticlesPainter(_particlesCtrl.value),
              ),
            ),
          ),
          _buildNeonWaves(),
          SafeArea(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                _buildContent(),
                Positioned(
                  top: 8, right: 16,
                  child: _buildThemeButton(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Content ──────────────────────────────────────────────────────────────

  Widget _buildContent() {
    return BlocConsumer<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthSignUpAwaitingEmailConfirmation) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
              'Аккаунт создан. Мы отправили письмо на ${state.email}. '
              'Откройте ссылку в письме, затем войдите.',
            ),
            backgroundColor: Colors.black87,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
          ));
          if (context.canPop()) context.pop();
          return;
        }
        if (state is AuthOAuthDismissed) {
          setState(() { _googleInProgress = false; _appleInProgress = false; });
          return;
        }
        if (state is! AuthLoading) {
          setState(() { _googleInProgress = false; _appleInProgress = false; });
        }
        if (state is AuthAuthenticated) {
          if (_authHandled) return;
          _authHandled = true;
          context.go('/home/feed');
          return;
        }
        if (state is AuthError) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(state.message),
            backgroundColor: Colors.black87,
            behavior: SnackBarBehavior.floating,
          ));
        }
      },
      builder: (context, state) {
        final loading = state is AuthLoading;
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              const SizedBox(height: 32),
              _buildLogo(),
              const SizedBox(height: 28),
              _buildPanel(loading),
              const SizedBox(height: 24),
              _buildLoginLink(),
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  // ─── Logo ─────────────────────────────────────────────────────────────────

  Widget _buildLogo() {
    return AnimatedBuilder(
      animation: _entranceCtrl,
      builder: (_, __) => FadeTransition(
        opacity: _logoFade,
        child: ScaleTransition(
          scale: _logoScale,
          child: Column(
            children: [
              ShaderMask(
                shaderCallback: (r) => const LinearGradient(
                  colors: [_C.green, _C.cyan],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ).createShader(r),
                child: Text('TMR TAU',
                  style: GoogleFonts.orbitron(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 4,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text('Создай аккаунт',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: _C.w60,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Glass Panel ──────────────────────────────────────────────────────────

  Widget _buildPanel(bool loading) {
    return AnimatedBuilder(
      animation: _entranceCtrl,
      builder: (_, __) => FadeTransition(
        opacity: _panelFade,
        child: SlideTransition(
          position: _panelSlide,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  color: _C.w08,
                  border: Border.all(color: _C.w15, width: 1),
                ),
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildStepIndicator(),
                    const SizedBox(height: 24),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 320),
                      transitionBuilder: (child, anim) {
                        final offsetAnim = Tween<Offset>(
                          begin: const Offset(0.08, 0),
                          end: Offset.zero,
                        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic));
                        return FadeTransition(
                          opacity: anim,
                          child: SlideTransition(position: offsetAnim, child: child),
                        );
                      },
                      child: _step == 0
                          ? _buildStep0(key: const ValueKey(0), loading: loading)
                          : _buildStep1(key: const ValueKey(1), loading: loading),
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

  // ─── Step Indicator ───────────────────────────────────────────────────────

  Widget _buildStepIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _StepDot(active: _step == 0, done: _step > 0),
        const SizedBox(width: 8),
        _StepDot(active: _step == 1, done: false),
      ],
    );
  }

  // ─── Step 0: Name + Social ────────────────────────────────────────────────

  Widget _buildStep0({required Key key, required bool loading}) {
    final appleAvailable = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Как вас зовут?',
          style: GoogleFonts.inter(
            fontSize: 18, fontWeight: FontWeight.w700, color: _C.white,
          ),
        ),
        const SizedBox(height: 4),
        Text('Это имя увидят другие пользователи',
          style: GoogleFonts.inter(fontSize: 13, color: _C.w60),
        ),
        const SizedBox(height: 20),
        _NeonTextField(
          controller: _nameController,
          focusNode: _nameFocus,
          label: 'Имя',
          hint: 'Например: Айгерим',
          prefixIcon: Icons.person_outline_rounded,
          accentColor: _C.green,
          error: _nameError,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) { if (_nameError != null) setState(() => _nameError = null); },
          onSubmitted: (_) => _residentFocus.requestFocus(),
        ),
        const SizedBox(height: 16),
        _NeonTextField(
          controller: _residentNumberController,
          focusNode: _residentFocus,
          label: 'Номер жителя',
          hint: 'Необязательно, например: 12345',
          prefixIcon: Icons.badge_outlined,
          accentColor: _C.cyan,
          error: null,
          textCapitalization: TextCapitalization.none,
          onSubmitted: (_) => _nextStep(),
        ),
        const SizedBox(height: 8),
        Text(
          'Если у вас есть городской номер жителя — укажите его; он будет в профиле.',
          style: GoogleFonts.inter(fontSize: 12, color: _C.w40),
        ),
        const SizedBox(height: 24),
        _ActionButton(
          label: 'Продолжить',
          loading: false,
          gradient: const LinearGradient(colors: [_C.green, _C.cyan]),
          shimmerAnim: _shimmerAnim,
          scaleCtrl: _btnScaleCtrl,
          scaleAnim: _btnScale,
          onTap: loading ? null : _nextStep,
        ),
        const SizedBox(height: 20),
        _Divider(text: 'или войти через'),
        const SizedBox(height: 16),
        Row(
          children: [
            if (appleAvailable) ...[
              Expanded(
                child: _SocialButton(
                  icon: const FaIcon(
                    FontAwesomeIcons.apple,
                    size: 16,
                    color: _C.w60,
                  ),
                  label: 'Apple',
                  loading: _appleInProgress,
                  onTap: loading ? null : () {
                    setState(() => _appleInProgress = true);
                    context.read<AuthBloc>().add(
                          const AuthSignInWithAppleRequested(),
                        );
                  },
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: _SocialButton(
                icon: const FaIcon(
                  FontAwesomeIcons.google,
                  size: 16,
                  color: _C.w60,
                ),
                label: 'Google',
                loading: _googleInProgress,
                onTap: loading ? null : () {
                  setState(() => _googleInProgress = true);
                  context.read<AuthBloc>().add(
                        const AuthSignInWithGoogleRequested(),
                      );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ─── Step 1: Email + Password ─────────────────────────────────────────────

  Widget _buildStep1({required Key key, required bool loading}) {
    final name = _nameController.text.trim();
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _C.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _C.green.withValues(alpha: 0.35), width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.person_rounded, size: 14, color: _C.green),
                  const SizedBox(width: 6),
                  Text(name,
                    style: GoogleFonts.inter(
                      fontSize: 13, fontWeight: FontWeight.w600, color: _C.green,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => setState(() => _step = 0),
              child: Text('Изменить',
                style: GoogleFonts.inter(
                  fontSize: 12, color: _C.w60,
                  decoration: TextDecoration.underline,
                  decorationColor: _C.w60,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _NeonTextField(
          controller: _emailController,
          focusNode: _emailFocus,
          label: 'Email',
          hint: 'example@mail.com',
          prefixIcon: Icons.alternate_email_rounded,
          accentColor: _C.cyan,
          error: _emailError,
          keyboardType: TextInputType.emailAddress,
          onChanged: (_) { if (_emailError != null) setState(() => _emailError = null); },
          onSubmitted: (_) => FocusScope.of(context).requestFocus(_passwordFocus),
        ),
        const SizedBox(height: 14),
        _NeonTextField(
          controller: _passwordController,
          focusNode: _passwordFocus,
          label: 'Пароль',
          hint: 'Минимум 6 символов',
          prefixIcon: Icons.lock_outline_rounded,
          accentColor: _C.pink,
          error: _passwordError,
          obscureText: _obscurePassword,
          suffixIcon: _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          onSuffixTap: () => setState(() => _obscurePassword = !_obscurePassword),
          onChanged: (_) { if (_passwordError != null) setState(() => _passwordError = null); },
          onSubmitted: (_) => FocusScope.of(context).requestFocus(_confirmFocus),
        ),
        const SizedBox(height: 14),
        _NeonTextField(
          controller: _confirmController,
          focusNode: _confirmFocus,
          label: 'Повторите пароль',
          hint: '••••••••',
          prefixIcon: Icons.lock_outline_rounded,
          accentColor: _C.orange,
          error: _confirmError,
          obscureText: _obscureConfirm,
          suffixIcon: _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          onSuffixTap: () => setState(() => _obscureConfirm = !_obscureConfirm),
          onChanged: (_) { if (_confirmError != null) setState(() => _confirmError = null); },
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 24),
        _ActionButton(
          label: 'Создать аккаунт',
          loading: loading,
          gradient: const LinearGradient(colors: [_C.pink, _C.orange]),
          shimmerAnim: _shimmerAnim,
          scaleCtrl: _btnScaleCtrl,
          scaleAnim: _btnScale,
          onTap: loading ? null : _submit,
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'Регистрируясь, вы соглашаетесь с\nПравилами использования и Политикой конфиденциальности',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 11, color: _C.w40, height: 1.5),
          ),
        ),
      ],
    );
  }

  // ─── Bottom "Already have account" link ───────────────────────────────────

  Widget _buildLoginLink() {
    return AnimatedBuilder(
      animation: _entranceCtrl,
      builder: (_, __) => FadeTransition(
        opacity: _panelFade,
        child: GestureDetector(
          onTap: () => context.popOrGo('/login'),
          child: RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: GoogleFonts.inter(fontSize: 14, color: _C.w60),
              children: [
                const TextSpan(text: 'Уже есть аккаунт? '),
                TextSpan(
                  text: 'Войти',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _C.cyan,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Theme Button ─────────────────────────────────────────────────────────

  void _showThemeBottomSheet() {
    final themeNotifier = context.read<ThemeIndexNotifier>();
    showThemePickerSheet(
      context,
      currentIndex: themeNotifier.value,
      onSelect: themeNotifier.setIndex,
      onAddCustom: () async {
        try {
          final picker = ImagePicker();
          final xFile = await picker.pickImage(source: ImageSource.gallery);
          if (xFile == null || !mounted) return;
          final bytes = await xFile.readAsBytes();
          if (!mounted) return;
          await themeNotifier.setCustomThemeFromImageBytes(bytes);
        } on PlatformException catch (e, st) {
          debugPrint('RegisterPage custom theme pick: $e\n$st');
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
          debugPrint('RegisterPage custom theme pick: $e\n$st');
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

  Widget _buildThemeButton() {
    return AnimatedBuilder(
      animation: Listenable.merge([_themeScaleCtrl, _themeGlowCtrl]),
      builder: (_, __) => Transform.scale(
        scale: _themeScale.value,
        child: GestureDetector(
          onTapDown: (_) => _themeScaleCtrl.forward(),
          onTapUp: (_) {
            _themeScaleCtrl.reverse();
            _showThemeBottomSheet();
          },
          onTapCancel: () => _themeScaleCtrl.reverse(),
          child: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _C.w08,
              border: Border.all(
                color: _C.cyan.withValues(alpha: _themeGlow.value * 0.6), width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: _C.cyan.withValues(alpha: _themeGlow.value * 0.25),
                  blurRadius: 12,
                ),
              ],
            ),
            child: const Icon(Icons.palette_outlined, color: _C.cyan, size: 20),
          ),
        ),
      ),
    );
  }

  // ─── Decorative Layers ────────────────────────────────────────────────────

  Widget _buildGlowSpots() {
    return Positioned.fill(
      child: CustomPaint(painter: _GlowSpotsPainter()),
    );
  }

  Widget _buildNeonWaves() {
    return Positioned(
      left: 0, right: 0, bottom: 0, height: 180,
      child: CustomPaint(painter: _NeonWavesPainter()),
    );
  }
}

// ─── Step Dot ─────────────────────────────────────────────────────────────────

class _StepDot extends StatelessWidget {
  const _StepDot({required this.active, required this.done});
  final bool active;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      width: active ? 28 : 8,
      height: 8,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        gradient: active
            ? const LinearGradient(colors: [_C.green, _C.cyan])
            : null,
        color: active ? null : (done ? _C.green : _C.w40),
      ),
    );
  }
}

// ─── Neon TextField ───────────────────────────────────────────────────────────

class _NeonTextField extends StatelessWidget {
  const _NeonTextField({
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.hint,
    required this.prefixIcon,
    required this.accentColor,
    this.error,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.obscureText = false,
    this.suffixIcon,
    this.onSuffixTap,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final String hint;
  final IconData prefixIcon;
  final Color accentColor;
  final String? error;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final bool obscureText;
  final IconData? suffixIcon;
  final VoidCallback? onSuffixTap;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final focused = focusNode.hasFocus;
    final hasError = error != null;
    final borderColor = hasError
        ? _C.pink
        : focused
            ? accentColor
            : const Color(0xFFE5E7EB);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: borderColor.withValues(alpha: focused ? 1.0 : 0.9),
              width: focused ? 1.5 : 1.0,
            ),
            color: focused ? _C.fieldFillFocused : _C.fieldFill,
            boxShadow: focused
                ? [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.22),
                      blurRadius: 14,
                    )
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            obscureText: obscureText,
            keyboardType: keyboardType,
            textCapitalization: textCapitalization,
            style: GoogleFonts.inter(
              fontSize: 15,
              color: _C.fieldText,
              fontWeight: FontWeight.w500,
            ),
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            cursorColor: accentColor,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: InputBorder.none,
              labelText: label,
              labelStyle: GoogleFonts.inter(
                fontSize: 13,
                color: focused ? accentColor : _C.fieldLabelMuted,
                fontWeight: FontWeight.w500,
              ),
              hintText: hint,
              hintStyle: GoogleFonts.inter(
                fontSize: 13,
                color: _C.fieldHint,
              ),
              prefixIcon: Icon(
                prefixIcon,
                size: 18,
                color: focused ? accentColor : _C.fieldLabelMuted,
              ),
              suffixIcon: suffixIcon != null
                  ? GestureDetector(
                      onTap: onSuffixTap,
                      child: Icon(
                        suffixIcon,
                        size: 18,
                        color: focused ? accentColor : _C.fieldLabelMuted,
                      ),
                    )
                  : null,
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Text(error!,
              style: GoogleFonts.inter(
                fontSize: 11, color: _C.pink, fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Action Button ────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.loading,
    required this.gradient,
    required this.shimmerAnim,
    required this.scaleCtrl,
    required this.scaleAnim,
    required this.onTap,
  });

  final String label;
  final bool loading;
  final LinearGradient gradient;
  final Animation<double> shimmerAnim;
  final AnimationController scaleCtrl;
  final Animation<double> scaleAnim;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: scaleAnim,
      builder: (_, __) => Transform.scale(
        scale: scaleAnim.value,
        child: GestureDetector(
          onTapDown: (_) { if (onTap != null) scaleCtrl.forward(); },
          onTapUp: (_) { scaleCtrl.reverse(); onTap?.call(); },
          onTapCancel: () => scaleCtrl.reverse(),
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: onTap != null ? gradient : null,
              color: onTap == null ? _C.w15 : null,
              boxShadow: onTap != null
                  ? [
                      BoxShadow(
                        color: gradient.colors.first.withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      )
                    ]
                  : [],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                children: [
                  Center(
                    child: loading
                        ? const SizedBox(
                            height: 22, width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Text(label,
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _C.white,
                              letterSpacing: 0.3,
                            ),
                          ),
                  ),
                  if (!loading && onTap != null)
                    AnimatedBuilder(
                      animation: shimmerAnim,
                      builder: (_, __) => Positioned.fill(
                        child: CustomPaint(
                          painter: _ShimmerPainter(shimmerAnim.value),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Social Button ────────────────────────────────────────────────────────────

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.icon,
    required this.label,
    required this.loading,
    required this.onTap,
  });

  final Widget icon;
  final String label;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: _C.w08,
          border: Border.all(color: _C.w15, width: 1),
        ),
        child: Center(
          child: loading
              ? const SizedBox(
                  height: 18, width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    icon,
                    const SizedBox(width: 8),
                    Text(label,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _C.w60,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ─── Divider ──────────────────────────────────────────────────────────────────

class _Divider extends StatelessWidget {
  const _Divider({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: _C.w15, thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(text,
            style: GoogleFonts.inter(fontSize: 12, color: _C.w40),
          ),
        ),
        Expanded(child: Divider(color: _C.w15, thickness: 1)),
      ],
    );
  }
}

// ─── Painters (identical to LoginPage) ───────────────────────────────────────

class _ParticlesPainter extends CustomPainter {
  _ParticlesPainter(this.t);
  final double t;

  static final _rng = math.Random(42);
  static final _particles = List.generate(28, (i) => [
    _rng.nextDouble(), // x
    _rng.nextDouble(), // y
    _rng.nextDouble() * 0.6 + 0.2, // speed
    _rng.nextDouble() * 2.5 + 0.8, // size
    _rng.nextDouble(), // phase
    _rng.nextInt(3).toDouble(), // color index
  ]);

  static const _colors = [
    Color(0xFF00E5A0),
    Color(0xFF00E5FF),
    Color(0xFFE91E8C),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in _particles) {
      final x = p[0] * size.width;
      final rawY = p[1] - p[2] * t;
      final y = (rawY % 1.0) * size.height;
      final sz = p[3];
      final phase = p[4];
      final ci = p[5].toInt();
      final opacity = (0.3 + 0.4 * math.sin((t + phase) * math.pi * 2)).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = _colors[ci % _colors.length].withValues(alpha: opacity.toDouble())
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(x, y), sz, paint);
    }
  }

  @override
  bool shouldRepaint(_ParticlesPainter old) => old.t != t;
}

class _GlowSpotsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final spots = [
      (0.15, 0.20, const Color(0xFF00E5A0), 220.0),
      (0.85, 0.15, const Color(0xFF00E5FF), 180.0),
      (0.10, 0.75, const Color(0xFFE91E8C), 160.0),
      (0.80, 0.80, const Color(0xFFFF6B35), 140.0),
    ];
    for (final (rx, ry, color, r) in spots) {
      final paint = Paint()
        ..shader = RadialGradient(colors: [
          color.withValues(alpha: 0.18),
          Colors.transparent,
        ]).createShader(Rect.fromCircle(
          center: Offset(rx * size.width, ry * size.height), radius: r));
      canvas.drawCircle(
        Offset(rx * size.width, ry * size.height), r, paint);
    }
  }

  @override
  bool shouldRepaint(_GlowSpotsPainter _) => false;
}

class _NeonWavesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paints = [
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.transparent, const Color(0xFF00E5A0).withValues(alpha: 0.08)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
        ..style = PaintingStyle.fill,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.transparent, const Color(0xFF00E5FF).withValues(alpha: 0.06)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
        ..style = PaintingStyle.fill,
    ];

    final offsets = [0.0, 20.0];
    for (int i = 0; i < 2; i++) {
      final path = Path();
      final off = offsets[i];
      path.moveTo(0, size.height * 0.55 + off);
      path.cubicTo(
        size.width * 0.25, size.height * 0.40 + off,
        size.width * 0.75, size.height * 0.60 + off,
        size.width, size.height * 0.45 + off,
      );
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
      path.close();
      canvas.drawPath(path, paints[i]);
    }
  }

  @override
  bool shouldRepaint(_NeonWavesPainter _) => false;
}

class _ShimmerPainter extends CustomPainter {
  _ShimmerPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment(t - 0.6, 0),
        end: Alignment(t + 0.6, 0),
        colors: [
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: 0.12),
          Colors.white.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(_ShimmerPainter old) => old.t != t;
}
