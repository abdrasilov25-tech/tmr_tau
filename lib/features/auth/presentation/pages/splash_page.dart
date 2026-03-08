import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../bloc/auth_bloc.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with TickerProviderStateMixin {
  Timer? _timeout;
  late AnimationController _logoController;
  late AnimationController _fadeOutController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  bool _navigating = false;

  @override
  void initState() {
    super.initState();

    // Появление логотипа: масштаб + прозрачность (как в TikTok)
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.05).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: Curves.easeOutBack,
      ),
    );
    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    // Плавное исчезновение перед переходом
    _fadeOutController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _logoController.forward();

    // Минимальное время показа сплэша
    _timeout = Timer(const Duration(milliseconds: 2500), () {
      if (!mounted || _navigating) return;
      _navigateFromSplash();
    });
  }

  void _navigateFromSplash() {
    if (_navigating) return;
    _navigating = true;
    _timeout?.cancel();

    final state = context.read<AuthBloc>().state;
    if (state is AuthAuthenticated) {
      _goAfterFadeOut('/home/feed');
    } else {
      _goAfterFadeOut('/login');
    }
  }

  void _goAfterFadeOut(String route) {
    _fadeOutController.forward();
    _fadeOutController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        context.go(route);
      }
    });
  }

  @override
  void dispose() {
    _timeout?.cancel();
    _logoController.dispose();
    _fadeOutController.dispose();
    super.dispose();
  }

  void _onAuthStateChanged(BuildContext context, AuthState state) {
    if (_navigating) return;
    if (state is AuthAuthenticated || state is AuthUnauthenticated ||
        state is AuthError) {
      _timeout?.cancel();
      // Небольшая задержка, чтобы анимация появления успела завершиться
      Future.delayed(const Duration(milliseconds: 400), () {
        if (!mounted || _navigating) return;
        _navigateFromSplash();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listenWhen: (prev, state) =>
          state is AuthAuthenticated ||
          state is AuthUnauthenticated ||
          state is AuthError,
      listener: _onAuthStateChanged,
      child: AnimatedBuilder(
        animation: Listenable.merge([_logoController, _fadeOutController]),
        builder: (context, child) {
          final fadeOut = 1.0 - _fadeOutController.value;
          return Container(
            color: Colors.black,
            child: Opacity(
              opacity: _opacityAnimation.value * fadeOut,
              child: Center(
                child: Transform.scale(
                  scale: _scaleAnimation.value,
                  child: Image.asset(
                    'assets/icons.png',
                    width: 160,
                    height: 160,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
