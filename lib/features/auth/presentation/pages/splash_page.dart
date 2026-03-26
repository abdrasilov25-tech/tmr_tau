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
  static const _minSplash = Duration(milliseconds: 600);

  late final DateTime _splashStartedAt;
  late AnimationController _logoController;
  late AnimationController _fadeOutController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    _splashStartedAt = DateTime.now();

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

    _fadeOutController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    _logoController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scheduleNavigateFromAuth();
    });
  }

  /// Ждём конец проверки сессии и минимальное время бренд-анимации; без искусственных 2.5 с.
  void _scheduleNavigateFromAuth() {
    if (!mounted || _navigating) return;

    final state = context.read<AuthBloc>().state;
    if (state is AuthLoading) return;

    final elapsed = DateTime.now().difference(_splashStartedAt);
    if (elapsed < _minSplash) {
      Future<void>.delayed(_minSplash - elapsed, () {
        if (mounted) _scheduleNavigateFromAuth();
      });
      return;
    }

    _navigateFromSplash();
  }

  void _navigateFromSplash() {
    if (_navigating) return;
    _navigating = true;

    final state = context.read<AuthBloc>().state;
    final route = state is AuthAuthenticated ? '/home/feed' : '/login';
    _goAfterFadeOut(route);
  }

  void _goAfterFadeOut(String route) {
    _fadeOutController.forward();
    void listener(AnimationStatus status) {
      if (status == AnimationStatus.completed && mounted) {
        _fadeOutController.removeStatusListener(listener);
        context.go(route);
      }
    }

    _fadeOutController.addStatusListener(listener);
  }

  @override
  void dispose() {
    _logoController.dispose();
    _fadeOutController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listenWhen: (prev, state) =>
          state is AuthAuthenticated ||
          state is AuthUnauthenticated ||
          state is AuthError,
      listener: (context, state) {
        if (_navigating) return;
        // Даём кадру сменить состояние, затем снова проверяем минимальное время сплэша.
        Future<void>.delayed(const Duration(milliseconds: 120), () {
          if (mounted) _scheduleNavigateFromAuth();
        });
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: AnimatedBuilder(
            animation: Listenable.merge([_logoController, _fadeOutController]),
            builder: (context, child) {
              final fadeOut = 1.0 - _fadeOutController.value;
              return Opacity(
                opacity: _opacityAnimation.value * fadeOut,
                child: Center(
                  child: Transform.scale(
                    scale: _scaleAnimation.value,
                    child: Image.asset(
                      'assets/icons.png',
                      width: 160,
                      height: 160,
                      cacheWidth: 320,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.image_outlined,
                        size: 120,
                        color: Colors.white54,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
