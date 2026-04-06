import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import 'deep_link_parser.dart';

/// Подписка на App / Universal links и навигация через [GoRouter].
final class DeepLinkCoordinator {
  DeepLinkCoordinator({
    required GoRouter router,
    required Set<String> httpsHosts,
  })  : _router = router,
        _httpsHosts = httpsHosts;

  final GoRouter _router;
  final Set<String> _httpsHosts;
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;

  Future<void> init() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        _handle(initial);
      }
    } catch (e, st) {
      debugPrint('Deep link initial: $e $st');
    }

    await _sub?.cancel();
    _sub = _appLinks.uriLinkStream.listen(
      _handle,
      onError: (Object e, StackTrace st) => debugPrint('Deep link stream: $e'),
    );
  }

  void _handle(Uri uri) {
    final loc = deepLinkToGoLocation(uri, httpsHosts: _httpsHosts);
    if (loc == null || loc == '/') {
      return;
    }
    scheduleMicrotask(() {
      try {
        _router.go(loc);
      } catch (e, st) {
        debugPrint('Deep link go($loc): $e $st');
      }
    });
  }

  void dispose() {
    unawaited(_sub?.cancel());
    _sub = null;
  }
}
