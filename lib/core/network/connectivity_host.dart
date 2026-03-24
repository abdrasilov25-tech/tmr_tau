import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Наследуемое состояние «офлайн по интерфейсу» для потомков [MaterialApp].
class ConnectivityScope extends InheritedWidget {
  const ConnectivityScope({
    required this.isOffline,
    required super.child,
    super.key,
  });

  final bool isOffline;

  static bool isOfflineOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ConnectivityScope>();
    return scope?.isOffline ?? false;
  }

  @override
  bool updateShouldNotify(ConnectivityScope oldWidget) =>
      oldWidget.isOffline != isOffline;
}

/// Слушает [Connectivity] без внешних API-ключей.
class ConnectivityHost extends StatefulWidget {
  const ConnectivityHost({super.key, required this.child});

  final Widget child;

  @override
  State<ConnectivityHost> createState() => _ConnectivityHostState();
}

class _ConnectivityHostState extends State<ConnectivityHost> {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _offline = false;
  /// Плагин недоступен (hot restart, web desktop, или не сделан pod install / clean build).
  bool _connectivityUnavailable = false;

  static bool _resultsOffline(List<ConnectivityResult> results) {
    if (results.isEmpty) return true;
    return !results.any(
      (r) =>
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.ethernet ||
          r == ConnectivityResult.vpn ||
          r == ConnectivityResult.other,
    );
  }

  void _apply(List<ConnectivityResult> results) {
    final offline = _resultsOffline(results);
    if (offline != _offline && mounted) {
      setState(() => _offline = offline);
    }
  }

  @override
  void initState() {
    super.initState();
    _initConnectivity();
  }

  Future<void> _initConnectivity() async {
    try {
      final initial = await _connectivity.checkConnectivity();
      if (!mounted || _connectivityUnavailable) return;
      _apply(initial);
    } on MissingPluginException {
      if (mounted) {
        setState(() {
          _connectivityUnavailable = true;
          _offline = false;
        });
      } else {
        _connectivityUnavailable = true;
        _offline = false;
      }
      return;
    } catch (_) {
      return;
    }

    try {
      _sub = _connectivity.onConnectivityChanged.listen(
        _apply,
        onError: (_) => _dropConnectivityPlugin(),
        cancelOnError: true,
      );
    } on MissingPluginException {
      _dropConnectivityPlugin();
    }
  }

  void _dropConnectivityPlugin() {
    _sub?.cancel();
    _sub = null;
    if (mounted) {
      setState(() {
        _connectivityUnavailable = true;
        _offline = false;
      });
    } else {
      _connectivityUnavailable = true;
      _offline = false;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ConnectivityScope(
      isOffline: _offline,
      // Баннер рисуется *над* [MaterialApp], поэтому здесь нет его Directionality — задаём явно.
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_offline && !_connectivityUnavailable)
              Material(
                color: Colors.orange.shade900,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.wifi_off_rounded,
                          color: Colors.orange.shade50,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Нет подключения к сети. Проверьте Wi‑Fi или мобильный интернет.',
                            style: TextStyle(
                              color: Colors.orange.shade50,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Expanded(child: widget.child),
          ],
        ),
      ),
    );
  }
}
