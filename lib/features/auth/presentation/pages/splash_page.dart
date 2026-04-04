import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/splash_qarmet_hero_backdrop.dart';
import '../../../../core/widgets/temirtau_tram_loader.dart';
import '../bloc/auth_bloc.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  static const _minSplash = Duration(milliseconds: 4200);

  late final DateTime _splashStartedAt;
  late AnimationController _fadeOutController;
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    _splashStartedAt = DateTime.now();

    _fadeOutController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scheduleNavigateFromAuth();
    });
  }

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
        Future<void>.delayed(const Duration(milliseconds: 120), () {
          if (mounted) _scheduleNavigateFromAuth();
        });
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF080A10),
        body: AnimatedBuilder(
          animation: _fadeOutController,
          builder: (context, child) {
            final fadeOut = 1.0 - _fadeOutController.value;
            return Opacity(
              opacity: fadeOut,
              child: child,
            );
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              const SplashQarmetHeroBackdrop(),
              SafeArea(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width - 40,
                      ),
                      child: const TemirtauTramLoader(height: 54),
                    ),
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
