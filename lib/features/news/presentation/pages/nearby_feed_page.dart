import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/services/geo_service.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../post/domain/entities/post_entity.dart';
import '../../../post/domain/repositories/post_repository.dart';
import '../../../product/data/services/payment_service.dart';

class NearbyFeedPage extends StatefulWidget {
  const NearbyFeedPage({super.key});

  @override
  State<NearbyFeedPage> createState() => _NearbyFeedPageState();
}

class _NearbyFeedPageState extends State<NearbyFeedPage> {
  static const List<int> _premiumRadii = <int>[5, 10, 20];
  bool _loading = true;
  bool _isPremium = false;
  int _radiusKm = 5;
  String? _error;
  List<PostEntity> _posts = const <PostEntity>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final userId = _currentUserId;
      final payment = context.read<PaymentService>();
      final geo = context.read<GeoService>();
      final postsRepo = context.read<PostRepository>();
      final isPremium = userId != null ? await payment.isPremiumActive() : false;
      if (!isPremium) _radiusKm = 5;
      final point = await geo.getCurrentLocation();
      if (point == null) {
        setState(() {
          _isPremium = isPremium;
          _loading = false;
          _posts = const <PostEntity>[];
          _error = 'Не удалось получить геолокацию. Включите GPS и разрешение.';
        });
        return;
      }
      final posts = await postsRepo.getPostsNearby(
            userLatitude: point.latitude,
            userLongitude: point.longitude,
            radiusKm: _radiusKm,
            currentUserId: userId,
            limit: 60,
          );
      if (!mounted) return;
      setState(() {
        _isPremium = isPremium;
        _posts = posts;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Ошибка загрузки: $e';
      });
    }
  }

  String? get _currentUserId {
    final s = context.read<AuthBloc>().state;
    return s is AuthAuthenticated ? s.user.id : null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Рядом'),
        actions: [
          if (!_isPremium)
            TextButton(
              onPressed: () => context.push('/premium'),
              child: const Text('Купить PRO'),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            child: Wrap(
              spacing: 8,
              children: (_isPremium ? _premiumRadii : const <int>[5]).map((r) {
                return ChoiceChip(
                  selected: _radiusKm == r,
                  label: Text('$r км'),
                  onSelected: (_) {
                    setState(() => _radiusKm = r);
                    _load();
                  },
                );
              }).toList(growable: false),
            ),
          ),
          if (!_isPremium)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.workspace_premium_outlined, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text('Бесплатно доступен радиус только 5 км.'),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (_posts.isEmpty) return const Center(child: Text('Поблизости постов нет'));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: _posts.length,
        itemBuilder: (context, index) {
          final p = _posts[index];
          return ListTile(
            onTap: () => context.push('/post/${p.id}', extra: p),
            title: Row(
              children: [
                Expanded(child: Text(p.caption.isEmpty ? 'Без текста' : p.caption)),
                if (p.isPromoted) const _PromotedBadge(),
              ],
            ),
            subtitle: Text(
              '${(p.distanceKm ?? 0).toStringAsFixed(1)} км · '
              'likes ${p.likesCount} · comments ${p.commentsCount}',
            ),
          );
        },
      ),
    );
  }
}

class _PromotedBadge extends StatelessWidget {
  const _PromotedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.purple.shade700,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'ПРОДВИЖЕНИЕ',
        style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
      ),
    );
  }
}
