import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/widgets/cached_avatar.dart';
import '../../features/auth/presentation/bloc/auth_bloc.dart';
import '../product/presentation/bloc/payment_cubit.dart';
import 'domain/entities/tap_game_leaderboard_entry.dart';
import 'domain/entities/tap_game_local_hall_entry.dart';
import 'domain/entities/tap_game_session_info.dart';
import 'domain/repositories/tap_game_local_hall_repository.dart';
import 'domain/repositories/tap_game_repository.dart';

/// «Тап судьбы» — соревнование по тапам с Qarmet-бустами и лидербордом.
class TapGameScreen extends StatefulWidget {
  const TapGameScreen({super.key});

  @override
  State<TapGameScreen> createState() => _TapGameScreenState();
}

class _TapGameScreenState extends State<TapGameScreen>
    with TickerProviderStateMixin {
  /// Совпадает с default на сервере (миграция tap_game_stamina).
  static const int kSessionFreeTaps = 180;
  static const int _boostCost = 8;
  static const int _jumpCost = 28;
  static const int _shieldCost = 14;
  static const Duration _pollInterval = Duration(seconds: 2);
  static const int _maxTapsPerSecond = 10;

  TapGameRepository get _repo => context.read<TapGameRepository>();
  TapGameLocalHallRepository get _localHallRepo =>
      context.read<TapGameLocalHallRepository>();

  String? _sessionId;
  TapGameSessionInfo? _session;
  int _displayScore = 0;
  int _stamina = kSessionFreeTaps;
  List<TapGameLeaderboardEntry> _leaderboard = const [];
  List<TapGameLocalHallEntry> _localHall = const [];
  bool _loading = true;
  String? _error;
  bool _finalized = false;
  bool _claimTried = false;
  bool _buyingStamina = false;
  bool _powerCelebrationOpen = false;
  DateTime? _boostLocalUntil;
  final List<DateTime> _tapTimestamps = [];
  Timer? _pollTimer;
  Timer? _tickTimer;
  late final AnimationController _pulse;
  late final AnimationController _rimSpin;
  late final AnimationController _tapJolt;

  // ── Combo system ───────────────────────────────────────────
  int _comboCount = 0;
  Timer? _comboResetTimer;
  static const Duration _comboWindow = Duration(milliseconds: 1200);
  static const int _comboThreshold = 5; // taps to activate combo

  String? get _userId {
    final s = context.read<AuthBloc>().state;
    return s is AuthAuthenticated ? s.user.id : null;
  }

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.92,
      upperBound: 1,
    )..value = 1;
    _rimSpin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 11),
    )..repeat();
    _tapJolt = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_userId != null) {
        unawaited(context.read<PaymentCubit>().refreshWallet(silent: true));
        unawaited(_bootstrap());
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _tickTimer?.cancel();
    _comboResetTimer?.cancel();
    _pulse.dispose();
    _rimSpin.dispose();
    _tapJolt.dispose();
    super.dispose();
  }

  Future<void> _reloadLocalHall() async {
    try {
      final list = await _localHallRepo.getTop50();
      if (mounted) setState(() => _localHall = list);
    } catch (_) {}
  }

  Future<void> _mergeLeaderboardIntoLocalHall() async {
    if (_leaderboard.isEmpty) return;
    try {
      await _localHallRepo.mergeFromLeaderboard(_leaderboard);
      await _reloadLocalHall();
    } catch (_) {}
  }

  void _recordLocalBestFromCurrentScore() {
    if (_displayScore <= 0) return;
    final uid = _userId;
    if (uid == null) return;
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated) return;
    unawaited(
      _localHallRepo
          .recordMyBestScore(
            userId: uid,
            displayName:
                auth.user.name ?? auth.user.username ?? auth.user.email,
            avatarUrl: auth.user.avatarUrl,
            score: _displayScore,
          )
          .then((_) => _reloadLocalHall()),
    );
  }

  void _notifyInsufficientQarmet() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Недостаточно Qarmet — пополните кошелёк'),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Купить',
          onPressed: () => context.push('/qarmet-wallet'),
        ),
      ),
    );
  }

  bool _isInsufficientQarmet(Object e) {
    final s = e.toString().toLowerCase();
    if (e is PostgrestException) {
      final m = e.message.toLowerCase();
      return m.contains('insufficient') || s.contains('insufficient_qarmet');
    }
    return s.contains('insufficient_qarmet') ||
        (s.contains('insufficient') && s.contains('qarmet'));
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final id = await _repo.getOrCreateSessionId();
      final info = await _repo.fetchSession(id);
      if (!mounted) return;
      setState(() {
        _sessionId = id;
        _session = info;
        _loading = false;
      });
      await _refreshLeaderboard();
      await _syncMyPlayState();
      await _reloadLocalHall();
      _startTimers();
    } catch (e, st) {
      debugPrint('TapGame bootstrap $e\n$st');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _humanError(e);
        });
      }
    }
  }

  void _startTimers() {
    _pollTimer?.cancel();
    _tickTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (!mounted || _sessionId == null) return;
      unawaited(_refreshLeaderboard());
      unawaited(_syncMyPlayState());
      unawaited(_maybeFinalizeAndClaim());
    });
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_boostLocalUntil != null &&
          DateTime.now().isAfter(_boostLocalUntil!)) {
        setState(() => _boostLocalUntil = null);
      }
      setState(() {});
    });
  }

  Future<void> _refreshLeaderboard() async {
    final sid = _sessionId;
    if (sid == null) return;
    try {
      final list = await _repo.fetchLeaderboard(sid, limit: 50);
      if (!mounted) return;
      setState(() => _leaderboard = list);
      unawaited(_mergeLeaderboardIntoLocalHall());
    } catch (e, st) {
      debugPrint('TapGame leaderboard $e\n$st');
    }
  }

  Future<void> _syncMyPlayState() async {
    final sid = _sessionId;
    final uid = _userId;
    if (sid == null || uid == null) return;
    try {
      final row = await _repo.fetchMyPlayState(sessionId: sid, userId: uid);
      if (!mounted) return;
      if (row == null) {
        setState(() {
          _displayScore = 0;
          _stamina = kSessionFreeTaps;
        });
        _recordLocalBestFromCurrentScore();
        return;
      }
      setState(() {
        _displayScore = row.score;
        _stamina = row.staminaRemaining;
      });
      _recordLocalBestFromCurrentScore();
    } catch (_) {}
  }

  Future<void> _maybeFinalizeAndClaim() async {
    final sid = _sessionId;
    final sess = _session;
    if (sid == null || sess == null || _finalized) return;
    if (DateTime.now().isBefore(sess.endsAt)) return;
    try {
      await _repo.finalizeSession(sid);
      if (!mounted) return;
      setState(() {
        _finalized = true;
        _session = TapGameSessionInfo(
          id: sess.id,
          startedAt: sess.startedAt,
          endsAt: sess.endsAt,
          isActive: false,
        );
      });
      if (!_claimTried) {
        _claimTried = true;
        final amount = await _repo.claimMyReward(sid);
        if (!mounted) return;
        if (amount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Награда: +$amount Qarmet'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
      await _refreshLeaderboard();
    } catch (e, st) {
      debugPrint('TapGame finalize/claim $e\n$st');
    }
  }

  bool get _boostActive {
    if (_boostLocalUntil == null) return false;
    return DateTime.now().isBefore(_boostLocalUntil!);
  }

  bool get _sessionOpen =>
      _session != null && _session!.isActive && DateTime.now().isBefore(_session!.endsAt);

  void _throttleOrTap() {
    if (!_sessionOpen || _userId == null) return;
    final need = _boostActive ? 2 : 1;
    if (_stamina < need) {
      HapticFeedback.selectionClick();
      _notifyInsufficientQarmet();
      context.push('/qarmet-wallet');
      return;
    }
    final now = DateTime.now();
    _tapTimestamps.removeWhere(
      (t) => now.difference(t) > const Duration(seconds: 1),
    );
    if (_tapTimestamps.length >= _maxTapsPerSecond) {
      return;
    }
    _tapTimestamps.add(now);
    _incrementCombo();
    unawaited(_sendTap());
  }

  void _incrementCombo() {
    _comboResetTimer?.cancel();
    setState(() => _comboCount++);
    _comboResetTimer = Timer(_comboWindow, () {
      if (mounted) setState(() => _comboCount = 0);
    });
  }

  int get _comboMultiplier {
    if (_comboCount >= 40) return 5;
    if (_comboCount >= 25) return 4;
    if (_comboCount >= 15) return 3;
    if (_comboCount >= _comboThreshold) return 2;
    return 1;
  }

  Future<void> _sendTap() async {
    final sid = _sessionId;
    if (sid == null) return;
    final delta = _boostActive ? 2 : 1;
    HapticFeedback.lightImpact();
    unawaited(_tapJolt.forward(from: 0));
    if (_comboMultiplier >= 3) {
      HapticFeedback.mediumImpact();
    }
    unawaited(_pulse.forward(from: _pulse.lowerBound).then((_) {
      if (mounted) _pulse.reverse();
    }));
    try {
      final r = await _repo.addScore(sessionId: sid, delta: delta);
      if (!mounted) return;
      setState(() {
        _displayScore = r.score;
        _stamina = r.staminaRemaining;
      });
      _recordLocalBestFromCurrentScore();
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('no_boost')) {
        try {
          final r = await _repo.addScore(sessionId: sid, delta: 1);
          if (!mounted) return;
          setState(() {
            _displayScore = r.score;
            _stamina = r.staminaRemaining;
          });
          _recordLocalBestFromCurrentScore();
        } catch (_) {}
      }
      if (msg.contains('insufficient_stamina')) {
        unawaited(_syncMyPlayState());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Не хватило энергии на этот тап'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
      if (msg.contains('rate_limited')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Слишком быстро — лимит сервера'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Future<void> _purchaseBoost() async {
    final sid = _sessionId;
    if (sid == null || !_sessionOpen) return;
    try {
      await _repo.spendQarmet(amount: _boostCost, reason: 'tap_game_boost');
      await _repo.applyBoost(sid);
      if (!mounted) return;
      setState(() {
        _boostLocalUntil = DateTime.now().add(const Duration(seconds: 30));
      });
      await _showPowerCelebration(
        context,
        emoji: '⚡',
        title: 'БУСТ x2',
        subtitle: '−$_boostCost Qarmet · 30 сек двойных тапов',
        accent: const Color(0xFFFFD54F),
      );
    } catch (e) {
      if (!mounted) return;
      if (_isInsufficientQarmet(e)) {
        _notifyInsufficientQarmet();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_humanError(e)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _purchaseJump() async {
    final sid = _sessionId;
    if (sid == null || !_sessionOpen) return;
    try {
      await _repo.spendQarmet(amount: _jumpCost, reason: 'tap_game_jump');
      final next = await _repo.applyJump(sid);
      if (!mounted) return;
      setState(() => _displayScore = next);
      await _showPowerCelebration(
        context,
        emoji: '🚀',
        title: 'ПРЫЖОК +1000',
        subtitle: '−$_jumpCost Qarmet',
        accent: const Color(0xFF7C4DFF),
      );
      unawaited(_syncMyPlayState());
    } catch (e) {
      if (!mounted) return;
      if (_isInsufficientQarmet(e)) {
        _notifyInsufficientQarmet();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_humanError(e)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _purchaseShield() async {
    final sid = _sessionId;
    if (sid == null || !_sessionOpen) return;
    try {
      await _repo.spendQarmet(amount: _shieldCost, reason: 'tap_game_shield');
      await _repo.applyShield(sid);
      if (!mounted) return;
      await _showPowerCelebration(
        context,
        emoji: '🛡',
        title: 'ЩИТ АКТИВЕН',
        subtitle: '−$_shieldCost Qarmet · 5 мин усиленной энергии',
        accent: const Color(0xFF26A69A),
      );
      await _refreshLeaderboard();
    } catch (e) {
      if (!mounted) return;
      if (_isInsufficientQarmet(e)) {
        _notifyInsufficientQarmet();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_humanError(e)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _buyStamina(int tier) async {
    final sid = _sessionId;
    if (sid == null || !_sessionOpen || _buyingStamina) return;
    setState(() => _buyingStamina = true);
    try {
      final r = await _repo.purchaseStamina(sessionId: sid, tier: tier);
      if (!mounted) return;
      setState(() {
        _stamina = r.stamina;
        _buyingStamina = false;
      });
      await _showPowerCelebration(
        context,
        emoji: '🔋',
        title: '+${r.added} ТАПОВ',
        subtitle: '−${r.spent} Qarmet · энергия пополнена',
        accent: const Color(0xFF42A5F5),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _buyingStamina = false);
        if (_isInsufficientQarmet(e)) {
          _notifyInsufficientQarmet();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_humanError(e)),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Future<void> _showPowerCelebration(
    BuildContext context, {
    required String emoji,
    required String title,
    required String subtitle,
    required Color accent,
  }) async {
    if (!context.mounted || _powerCelebrationOpen) return;
    _powerCelebrationOpen = true;
    HapticFeedback.heavyImpact();
    try {
      await showDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: true,
        barrierColor: Colors.black.withValues(alpha: 0.72),
        builder: (ctx) => _PowerFlash(
          emoji: emoji,
          title: title,
          subtitle: subtitle,
          accent: accent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _powerCelebrationOpen = false);
      } else {
        _powerCelebrationOpen = false;
      }
    }
  }

  Future<void> _manualClaim() async {
    final sid = _sessionId;
    if (sid == null) return;
    try {
      final amount = await _repo.claimMyReward(sid);
      if (!mounted) return;
      if (amount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Начислено $amount Qarmet'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Награда недоступна (не топ-3 или уже получено)'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_humanError(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _humanError(Object e) {
    final s = e.toString();
    if (e is PostgrestException) {
      final m = e.message.toLowerCase();
      if (m.contains('insufficient') || s.contains('insufficient_qarmet')) {
        return 'Недостаточно Qarmet';
      }
      if (s.contains('session_closed')) return 'Сессия закрыта';
      if (s.contains('session_not_finished')) return 'Сессия ещё идёт';
      if (s.contains('jump_cooldown')) return 'Прыжок на перезарядке';
      if (s.contains('rate_limited')) return 'Слишком быстро';
      if (s.contains('insufficient_stamina')) return 'Не хватило энергии';
      if (s.contains('invalid_stamina_tier')) return 'Неверный пакет энергии';
      return e.message;
    }
    if (s.contains('insufficient_qarmet')) return 'Недостаточно Qarmet';
    if (s.contains('insufficient_stamina')) return 'Не хватило энергии';
    return 'Ошибка: ${e.toString()}';
  }

  double get _sessionProgress {
    final s = _session;
    if (s == null) return 0;
    final total = s.endsAt.difference(s.startedAt).inMilliseconds;
    if (total <= 0) return 1;
    final gone = DateTime.now().difference(s.startedAt).inMilliseconds;
    return (gone / total).clamp(0.0, 1.0);
  }

  Duration get _remaining {
    final s = _session;
    if (s == null) return Duration.zero;
    final d = s.endsAt.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  @override
  Widget build(BuildContext context) {
    final uid = _userId;
    if (uid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Тап судьбы')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Войдите в аккаунт, чтобы играть.'),
          ),
        ),
      );
    }

    final needEnergy = _boostActive ? 2 : 1;
    final canTap = _sessionOpen && _stamina >= needEnergy;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Тап судьбы 🔥'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Кошелёк Qarmet',
            onPressed: () => context.push('/qarmet-wallet'),
            icon: const Icon(Icons.account_balance_wallet_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _bootstrap,
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    BlocSelector<PaymentCubit, PaymentUiState, int>(
                      selector: (s) => s.balance,
                      builder: (context, bal) {
                        if (bal >= 15) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                          child: Material(
                            color: Theme.of(context)
                                .colorScheme
                                .tertiaryContainer
                                .withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => context.push('/qarmet-wallet'),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.monetization_on_rounded,
                                      color: Colors.amber.shade800,
                                      size: 26,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Баланс $bal Qarmet — пополните, чтобы брать бусты и энергию.',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          height: 1.25,
                                        ),
                                      ),
                                    ),
                                    FilledButton(
                                      style: FilledButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 8,
                                        ),
                                      ),
                                      onPressed: () =>
                                          context.push('/qarmet-wallet'),
                                      child: const Text('Купить'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: () async {
                          final wallet = context.read<PaymentCubit>();
                          await _refreshLeaderboard();
                          await _syncMyPlayState();
                          if (!mounted) return;
                          await wallet.refreshWallet(silent: true);
                        },
                        child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    children: [
                      if (_session != null) _SessionHeader(
                        remaining: _remaining,
                        progress: _sessionProgress,
                        sessionOpen: _sessionOpen,
                      ),
                      const SizedBox(height: 12),
                      _MotivationStrip(
                        leaderboard: _leaderboard,
                        myUserId: uid,
                        myScore: _displayScore,
                      ),
                      const SizedBox(height: 12),
                      _EnergyCard(
                        stamina: _stamina,
                        starterTaps: kSessionFreeTaps,
                        buying: _buyingStamina,
                        enabled: _sessionOpen,
                        onTier: _buyStamina,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Очки: $_displayScore',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      if (_boostActive)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'Буст x2 активен',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      if (_comboMultiplier > 1)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: _ComboBadge(
                              key: ValueKey(_comboMultiplier),
                              multiplier: _comboMultiplier,
                              count: _comboCount,
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      Center(
                        child: _FateTapWheel(
                          rimSpin: _rimSpin,
                          tapJolt: _tapJolt,
                          pulse: _pulse,
                          canTap: canTap,
                          sessionOpen: _sessionOpen,
                          comboMultiplier: _comboMultiplier,
                          onTap: canTap
                              ? _throttleOrTap
                              : _sessionOpen
                                  ? () {
                                      _notifyInsufficientQarmet();
                                      context.push('/qarmet-wallet');
                                    }
                                  : null,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'До $_maxTapsPerSecond тапов/сек · 1 тап = 1 энергии (x2 при бусте)',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.6),
                            ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Усиления за Qarmet',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Списание с кошелька при нажатии',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.55),
                            ),
                      ),
                      const SizedBox(height: 8),
                      _BoostRow(
                        title: 'BOOST x2 · 30 с',
                        subtitle: 'Платно · мощная анимация при покупке',
                        cost: _boostCost,
                        enabled: _sessionOpen,
                        onPressed: _purchaseBoost,
                      ),
                      _BoostRow(
                        title: 'JUMP +1000 очков',
                        subtitle: 'Платный рывок в таблице',
                        cost: _jumpCost,
                        enabled: _sessionOpen,
                        onPressed: _purchaseJump,
                      ),
                      _BoostRow(
                        title: 'SHIELD · 5 мин',
                        subtitle: 'Быстрее копится энергия тапов',
                        cost: _shieldCost,
                        enabled: _sessionOpen,
                        onPressed: _purchaseShield,
                      ),
                      if (!_sessionOpen) ...[
                        const SizedBox(height: 16),
                        FilledButton.tonal(
                          onPressed: _manualClaim,
                          child: const Text('Проверить награду'),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Text(
                        'Онлайн этой сессии',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 8),
                      ..._leaderboard.map((e) => _LeaderTile(entry: e)),
                      if (_leaderboard.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            'Пока нет игроков в этой сессии',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.5),
                                ),
                          ),
                        ),
                    ],
                        ),
                      ),
                    ),
                    _LocalHallPanel(
                      entries: _localHall,
                      myUserId: uid,
                    ),
                  ],
                ),
    );
  }
}

class _FateTapWheel extends StatelessWidget {
  const _FateTapWheel({
    required this.rimSpin,
    required this.tapJolt,
    required this.pulse,
    required this.canTap,
    required this.sessionOpen,
    required this.comboMultiplier,
    required this.onTap,
  });

  final AnimationController rimSpin;
  final AnimationController tapJolt;
  final AnimationController pulse;
  final bool canTap;
  final bool sessionOpen;
  final int comboMultiplier;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 248,
      height: 248,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          AnimatedBuilder(
            animation: rimSpin,
            builder: (context, _) {
              return Transform.rotate(
                angle: rimSpin.value * 2 * math.pi,
                child: CustomPaint(
                  size: const Size(248, 248),
                  painter: _FateRimPainter(
                    alive: canTap,
                    comboTier: comboMultiplier,
                  ),
                ),
              );
            },
          ),
          Positioned(
            child: AnimatedBuilder(
              animation: Listenable.merge([pulse, tapJolt, rimSpin]),
              builder: (context, _) {
                final j = CurvedAnimation(
                  parent: tapJolt,
                  curve: Curves.easeOutCubic,
                );
                final bump = 1.0 + 0.14 * j.value;
                final scale = pulse.value * bump;
                final colors = !sessionOpen
                    ? [Colors.grey.shade500, Colors.grey.shade700]
                    : comboMultiplier >= 4
                        ? const [Color(0xFFFFE066), Color(0xFFFF6B35)]
                        : comboMultiplier >= 2
                            ? const [Color(0xFFFF6B35), Color(0xFF9D4EDD)]
                            : const [Color(0xFFFF1744), Color(0xFF7B2CBF)];
                final glow = !sessionOpen
                    ? Colors.grey
                    : comboMultiplier >= 4
                        ? const Color(0xFFFFD700)
                        : const Color(0xFFE040FB);
                return Transform.scale(
                  scale: scale,
                  child: Material(
                    color: Colors.transparent,
                    elevation: canTap ? 12 : 2,
                    shadowColor: glow.withValues(alpha: 0.55),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onTap,
                      child: Ink(
                        width: 168,
                        height: 168,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: SweepGradient(
                            colors: [
                              colors[0],
                              colors[1],
                              colors[0],
                            ],
                            stops: const [0.0, 0.55, 1.0],
                            transform: GradientRotation(rimSpin.value * math.pi),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: glow.withValues(
                                alpha: canTap ? 0.55 : 0.2,
                              ),
                              blurRadius: canTap ? 36 : 12,
                              spreadRadius: canTap ? 2 : 0,
                            ),
                          ],
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.35),
                            width: 3,
                          ),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                !sessionOpen
                                    ? '⏱'
                                    : !canTap
                                        ? '💎'
                                        : comboMultiplier >= 4
                                            ? '🔥'
                                            : '✨',
                                style: const TextStyle(fontSize: 36),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                !sessionOpen
                                    ? 'ПАУЗА'
                                    : !canTap
                                        ? 'QARMET'
                                        : comboMultiplier >= 4
                                            ? 'ЖАРИ!'
                                            : 'ТАП!',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.2,
                                  height: 1.0,
                                  shadows: [
                                    Shadow(
                                      blurRadius: 8,
                                      color: Colors.black45,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
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
}

class _FateRimPainter extends CustomPainter {
  _FateRimPainter({required this.alive, required this.comboTier});

  final bool alive;
  final int comboTier;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    const segments = 12;
    final paint = Paint()..style = PaintingStyle.stroke;
    for (var i = 0; i < segments; i++) {
      final t = i / segments;
      paint.strokeWidth = 5;
      if (!alive) {
        paint.color = Color.lerp(Colors.grey.shade500, Colors.grey.shade700, t)!;
      } else {
        final hue = comboTier >= 3 ? 0.08 + t * 0.22 : 0.88 - t * 0.42;
        paint.color = HSVColor.fromAHSV(1, hue * 360, 0.88, 0.98).toColor();
      }
      final a0 = (i * 2 * math.pi / segments) - math.pi / 2;
      final a1 = ((i + 1) * 2 * math.pi / segments) - math.pi / 2;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r - 10),
        a0,
        a1 - a0,
        false,
        paint,
      );
    }
    final tick = Paint()
      ..color = Colors.white.withValues(alpha: alive ? 0.5 : 0.25)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 24; i++) {
      final a = (i * math.pi / 12) - math.pi / 2;
      final inner = r - 22;
      final outer = r - 14;
      canvas.drawLine(
        Offset(c.dx + inner * math.cos(a), c.dy + inner * math.sin(a)),
        Offset(c.dx + outer * math.cos(a), c.dy + outer * math.sin(a)),
        tick,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FateRimPainter oldDelegate) =>
      oldDelegate.alive != alive || oldDelegate.comboTier != comboTier;
}

class _LocalHallPanel extends StatelessWidget {
  const _LocalHallPanel({
    required this.entries,
    required this.myUserId,
  });

  final List<TapGameLocalHallEntry> entries;
  final String myUserId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 8,
      shadowColor: Colors.black38,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.95),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 12, 6),
              child: Row(
                children: [
                  Icon(Icons.emoji_events_rounded, color: Colors.amber.shade800),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Зал славы (на устройстве)',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                  Text(
                    'Топ-${TapGameLocalHallRepository.maxEntries}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: scheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              'Лучшие очки сохраняются локально и не сбрасываются при выходе.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 168,
              child: entries.isEmpty
                  ? Center(
                      child: Text(
                        'Играйте — рекорды появятся здесь',
                        style: TextStyle(
                          color: scheme.onSurface.withValues(alpha: 0.45),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                      itemCount: entries.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final e = entries[i];
                        final me = e.userId == myUserId;
                        return ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: scheme.primaryContainer,
                            child: Text(
                              '${i + 1}',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: scheme.onPrimaryContainer,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  e.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight:
                                        me ? FontWeight.w900 : FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (me)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Text(
                                    'ВЫ',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      color: scheme.primary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          trailing: Text(
                            '${e.bestScore}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionHeader extends StatelessWidget {
  const _SessionHeader({
    required this.remaining,
    required this.progress,
    required this.sessionOpen,
  });

  final Duration remaining;
  final double progress;
  final bool sessionOpen;

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      final h = d.inHours.toString().padLeft(2, '0');
      return '$h:$m:$s';
    }
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              sessionOpen ? 'Сессия' : 'Сессия завершена',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              sessionOpen ? _fmt(remaining) : '0:00',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: sessionOpen
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: sessionOpen ? progress : 1,
            minHeight: 8,
            backgroundColor: Colors.grey.shade200,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          sessionOpen
              ? 'Топ-3 получают 500 / 300 / 100 Qarmet'
              : 'Итоги подведены. Награды забираются автоматически или кнопкой ниже.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.65),
              ),
        ),
      ],
    );
  }
}

class _MotivationStrip extends StatelessWidget {
  const _MotivationStrip({
    required this.leaderboard,
    required this.myUserId,
    required this.myScore,
  });

  final List<TapGameLeaderboardEntry> leaderboard;
  final String myUserId;
  final int myScore;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (leaderboard.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.outline.withValues(alpha: 0.2)),
        ),
        child: Text(
          'Топ-3 в конце 10-минутной сессии получают 500, 300 и 100 Qarmet. '
          'Следи за таблицей — тапать «вслепую» невыгодно.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
        ),
      );
    }
    final leader = leaderboard.first;
    final idx = leaderboard.indexWhere((e) => e.userId == myUserId);
    final myRank = idx >= 0 ? idx + 1 : 0;
    final gap = leader.score - myScore;
    final gapClamped = gap < 0 ? 0 : gap;

    late final String line;
    if (myRank == 1) {
      line =
          'Ты лидер на ${leader.score} очках. Удержи 1 место до конца таймера — '
          'тогда 500 Qarmet твои (если никто не обгонит).';
    } else if (myRank > 0) {
      line =
          'Ты №$myRank в топе сессии. До лидера «${leader.displayName}»: примерно '
          '$gapClamped очков — добей разницу тапами или JUMP.';
    } else {
      line =
          'Тебя ещё нет в топе сессии. Лидер на ${leader.score} очках — '
          'тапай и догоняй, иначе награда уйдёт другим.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.tertiaryContainer.withValues(alpha: 0.5),
            scheme.secondaryContainer.withValues(alpha: 0.35),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Стратегия сессии',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            line,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }
}

class _EnergyCard extends StatelessWidget {
  const _EnergyCard({
    required this.stamina,
    required this.starterTaps,
    required this.buying,
    required this.enabled,
    required this.onTier,
  });

  final int stamina;
  final int starterTaps;
  final bool buying;
  final bool enabled;
  final void Function(int tier) onTier;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final denom = stamina <= 0
        ? starterTaps.toDouble()
        : (stamina < 400 ? 400.0 : stamina.toDouble());
    final frac = (stamina / denom).clamp(0.0, 1.0);

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Энергия тапов',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                Text(
                  '$stamina шт.',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: stamina <= 0 ? scheme.error : scheme.primary,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'В начале сессии — $starterTaps бесплатных тапов. Когда кончатся, '
              'тап не идёт в зачёт — докупи пакет или жди новую сессию.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.65),
                    height: 1.3,
                  ),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: frac,
                minHeight: 10,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Докупить энергию',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StaminaPackButton(
                  tier: 1,
                  cost: 15,
                  taps: 150,
                  enabled: enabled && !buying,
                  onPressed: () => onTier(1),
                ),
                _StaminaPackButton(
                  tier: 2,
                  cost: 39,
                  taps: 420,
                  enabled: enabled && !buying,
                  onPressed: () => onTier(2),
                ),
                _StaminaPackButton(
                  tier: 3,
                  cost: 89,
                  taps: 1100,
                  enabled: enabled && !buying,
                  onPressed: () => onTier(3),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StaminaPackButton extends StatelessWidget {
  const _StaminaPackButton({
    required this.tier,
    required this.cost,
    required this.taps,
    required this.enabled,
    required this.onPressed,
  });

  final int tier;
  final int cost;
  final int taps;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonal(
      onPressed: enabled ? onPressed : null,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '+$taps тапов',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          Text(
            '$cost Qarmet',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Одноразовое закрытие: иначе [TweenAnimationBuilder.onEnd] + барьер дают двойной pop
/// и ломают Navigator (keyReservation).
class _PowerFlash extends StatefulWidget {
  const _PowerFlash({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.accent,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final Color accent;

  @override
  State<_PowerFlash> createState() => _PowerFlashState();
}

class _PowerFlashState extends State<_PowerFlash> {
  static const _autoClose = Duration(milliseconds: 900);
  Timer? _autoPopTimer;
  bool _popped = false;

  @override
  void initState() {
    super.initState();
    _autoPopTimer = Timer(_autoClose, _popDialogOnce);
  }

  void _popDialogOnce() {
    if (!mounted || _popped) return;
    _popped = true;
    _autoPopTimer?.cancel();
    final nav = Navigator.of(context, rootNavigator: true);
    if (nav.canPop()) {
      nav.pop();
    }
  }

  @override
  void dispose() {
    _autoPopTimer?.cancel();
    _popped = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
        color: Colors.transparent,
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 720),
            curve: Curves.elasticOut,
            builder: (context, t, _) {
              final accent = widget.accent;
              return Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    child: Container(
                      width: 220 * t,
                      height: 220 * t,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.5 * t),
                            blurRadius: 56,
                            spreadRadius: 18 * t,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Transform.scale(
                    scale: 0.2 + 0.85 * t,
                    child: Opacity(
                      opacity: t.clamp(0.0, 1.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.emoji,
                            style: TextStyle(
                              fontSize: 92,
                              shadows: [
                                Shadow(
                                  blurRadius: 16,
                                  color: accent.withValues(alpha: 0.9),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            widget.title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Text(
                              widget.subtitle,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.82),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                height: 1.25,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
    );
  }
}

class _BoostRow extends StatelessWidget {
  const _BoostRow({
    required this.title,
    required this.subtitle,
    required this.cost,
    required this.enabled,
    required this.onPressed,
  });

  final String title;
  final String subtitle;
  final int cost;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: OutlinedButton(
        onPressed: enabled ? onPressed : null,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          alignment: Alignment.centerLeft,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: scheme.onSurface.withValues(alpha: 0.6),
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: scheme.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: scheme.error.withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                '−$cost QM',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  color: scheme.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComboBadge extends StatelessWidget {
  const _ComboBadge({super.key, required this.multiplier, required this.count});

  final int multiplier;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = switch (multiplier) {
      >= 5 => [const Color(0xFFFFD700), const Color(0xFFFF6B35)],
      4 => [const Color(0xFFFF6B35), const Color(0xFFAA00FF)],
      3 => [const Color(0xFFF72585), const Color(0xFF7209B7)],
      _ => [const Color(0xFF4361EE), const Color(0xFF3A0CA3)],
    };
    final label = switch (multiplier) {
      >= 5 => '🔥 MEGA COMBO x$multiplier',
      4 => '⚡ COMBO x$multiplier',
      3 => '💥 COMBO x$multiplier',
      _ => '✨ COMBO x$multiplier',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: colors.first.withValues(alpha: 0.5),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 15,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _LeaderTile extends StatelessWidget {
  const _LeaderTile({required this.entry});

  final TapGameLeaderboardEntry entry;

  @override
  Widget build(BuildContext context) {
    final medal = switch (entry.rank) {
      1 => '🥇',
      2 => '🥈',
      3 => '🥉',
      _ => '${entry.rank}.',
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    medal,
                    style: const TextStyle(fontSize: 16),
                    maxLines: 1,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            CachedAvatar(
              imageUrl: entry.avatarUrl,
              radius: 20,
              fallbackText: entry.displayName,
              enableLightboxOnTap: false,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (entry.shieldActive)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.shield, size: 18, color: Colors.teal),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 72,
              child: Text(
                '${entry.score}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
