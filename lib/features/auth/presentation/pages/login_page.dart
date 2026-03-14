import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../bloc/auth_bloc.dart';

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
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _obscurePassword = true;
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

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
    _emailFocus.addListener(() => setState(() {}));
    _passwordFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _scaleController.dispose();
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
          // Фон: градиент фиолетовый → розовый → оранжевый → жёлтый → бирюзовый
          _buildGradientBackground(),
          // Глубина: размытые светящиеся пятна
          _buildGlowSpots(),
          // Волнистые световые линии (неоновые волны)
          _buildNeonWaves(),
          // Контент поверх
          SafeArea(
            child: BlocConsumer<AuthBloc, AuthState>(
              listener: (context, state) {
                if (state is AuthAuthenticated) {
                  context.go('/home/feed');
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
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 56),
                        Text(
                          'tmr_tau',
                          style: GoogleFonts.poppins(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: _NeonColors.white,
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
                            color: _NeonColors.white60,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 48),
                        _NeonTextField(
                          controller: _emailController,
                          focusNode: _emailFocus,
                          isFocused: _emailFocus.hasFocus,
                          hint: 'Email',
                          keyboardType: TextInputType.emailAddress,
                          borderColor: _NeonColors.cyan,
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
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGradientBackground() {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _NeonColors.purple,
              const Color(0xFF8B2D9E),
              _NeonColors.pink,
              const Color(0xFFE85A4F),
              _NeonColors.orange,
              const Color(0xFFFFA726),
              _NeonColors.yellow,
              const Color(0xFF26C6DA),
              _NeonColors.teal,
            ],
            stops: const [0.0, 0.2, 0.35, 0.5, 0.6, 0.75, 0.85, 0.92, 1.0],
          ),
        ),
      ),
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

  static const _radius = 20.0;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: isFocused ? 1 : 0),
      duration: const Duration(milliseconds: 200),
      builder: (context, value, child) {
        final glowOpacity = 0.3 + 0.4 * value;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_radius),
            boxShadow: [
              BoxShadow(
                color: borderColor.withValues(alpha: glowOpacity),
                blurRadius: isFocused ? 20 : 8,
                spreadRadius: isFocused ? 1 : 0,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_radius),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(_radius),
                  border: Border.all(
                    color: borderColor.withValues(
                        alpha: isFocused ? 0.9 : 0.5),
                    width: isFocused ? 2 : 1.5,
                  ),
                  color: Colors.white.withValues(alpha: 0.12),
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
                      color: _NeonColors.white40,
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
                              color: _NeonColors.white60,
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
