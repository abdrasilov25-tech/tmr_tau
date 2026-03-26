import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../core/data/kazakhstan_regions.dart';
import '../../../../core/models/search_filters.dart';

/// Результат выбора места на листе (OLX-подобный сценарий).
sealed class KazakhstanLocationOutcome {
  const KazakhstanLocationOutcome();
}

/// Вся страна — сброс локации.
final class KazOutcomeWholeCountry extends KazakhstanLocationOutcome {
  const KazOutcomeWholeCountry();
}

/// Геолокация + радиус (как «рядом» в OLX).
final class KazOutcomeNearby extends KazakhstanLocationOutcome {
  const KazOutcomeNearby({
    required this.latitude,
    required this.longitude,
    required this.radiusKm,
  });

  final double latitude;
  final double longitude;
  final double radiusKm;
}

/// Область и опционально населённый пункт.
final class KazOutcomeRegion extends KazakhstanLocationOutcome {
  const KazOutcomeRegion({
    required this.regionId,
    this.localityName,
  });

  final String regionId;
  final String? localityName;
}

/// Свободный текст города (совместимость с ручным вводом).
final class KazOutcomeManualCity extends KazakhstanLocationOutcome {
  const KazOutcomeManualCity(this.city);
  final String city;
}

/// Лист выбора: страна → области → города.
class KazakhstanLocationSheet extends StatefulWidget {
  const KazakhstanLocationSheet({super.key});

  @override
  State<KazakhstanLocationSheet> createState() =>
      _KazakhstanLocationSheetState();
}

class _KazakhstanLocationSheetState extends State<KazakhstanLocationSheet> {
  /// 0 — главное меню, 1 — список областей, 2 — города выбранной области.
  int _step = 0;
  KzRegionEntry? _region;

  static const List<double> _radiusChoices = [5, 10, 25, 50, 100];

  Future<void> _onWholeCountry() async {
    Navigator.of(context).pop(const KazOutcomeWholeCountry());
  }

  Future<void> _onMyLocation() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Включите геолокацию'),
            action: SnackBarAction(
              label: 'Настройки',
              onPressed: Geolocator.openLocationSettings,
            ),
          ),
        );
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет доступа к геолокации')),
        );
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 14),
        ),
      );
      if (!mounted) return;
      final radius = await showDialog<double>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Радиус поиска'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: _radiusChoices
                .map(
                  (km) => ListTile(
                    title: Text('До $km км'),
                    onTap: () => Navigator.pop(ctx, km.toDouble()),
                  ),
                )
                .toList(growable: false),
          ),
        ),
      );
      if (!mounted || radius == null) return;
      Navigator.of(context).pop(
        KazOutcomeNearby(
          latitude: pos.latitude,
          longitude: pos.longitude,
          radiusKm: radius,
        ),
      );
    } on TimeoutException {
      final last = await Geolocator.getLastKnownPosition();
      if (!mounted) return;
      if (last != null) {
        final radius = await showDialog<double>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('Радиус поиска'),
            children: _radiusChoices
                .map(
                  (km) => SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, km.toDouble()),
                    child: Text('До $km км'),
                  ),
                )
                .toList(growable: false),
          ),
        );
        if (!mounted || radius == null) return;
        Navigator.of(context).pop(
          KazOutcomeNearby(
            latitude: last.latitude,
            longitude: last.longitude,
            radiusKm: radius,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось определить координаты')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка геолокации: $e')),
      );
    }
  }

  void _goRegions() => setState(() {
        _step = 1;
        _region = null;
      });

  void _pickRegion(KzRegionEntry r) => setState(() {
        _region = r;
        _step = 2;
      });

  void _back() {
    setState(() {
      if (_step == 2) {
        _step = 1;
        _region = null;
      } else if (_step == 1) {
        _step = 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final h = MediaQuery.of(context).size.height;

    return SafeArea(
      child: SizedBox(
        height: h * 0.88,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Row(
                children: [
                  if (_step > 0)
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: _back,
                    )
                  else
                    const SizedBox(width: 48),
                  Expanded(
                    child: Text(
                      _step == 0
                          ? 'Местоположение'
                          : _step == 1
                              ? 'Области Казахстана'
                              : (_region?.name ?? 'Населённые пункты'),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _step == 0
                  ? _buildHome(theme)
                  : _step == 1
                      ? _buildRegionList(theme)
                      : _buildLocalityList(theme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHome(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        ListTile(
          leading: Icon(Icons.public_rounded, color: theme.colorScheme.primary),
          title: const Text('Вся страна'),
          subtitle: const Text('Показать объявления по всему Казахстану'),
          onTap: _onWholeCountry,
        ),
        ListTile(
          leading: Icon(Icons.my_location_rounded, color: theme.colorScheme.primary),
          title: const Text('Моя геопозиция'),
          subtitle: const Text('Радиус вокруг текущих координат'),
          onTap: _onMyLocation,
        ),
        ListTile(
          leading: Icon(Icons.map_rounded, color: theme.colorScheme.primary),
          title: const Text('Выбрать область'),
          subtitle: const Text('Область и город / вся область'),
          onTap: _goRegions,
        ),
      ],
    );
  }

  Widget _buildRegionList(ThemeData theme) {
    final list = KazakhstanRegions.all;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final r = list[i];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Material(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(14),
            child: ListTile(
              leading: Icon(
                Icons.map_outlined,
                color: theme.colorScheme.primary,
              ),
              title: Text(r.name),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _pickRegion(r),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLocalityList(ThemeData theme) {
    final r = _region;
    if (r == null) return const SizedBox.shrink();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      children: [
        Material(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(14),
          child: ListTile(
            leading: Icon(
              Icons.public_rounded,
              color: theme.colorScheme.primary,
            ),
            title: Text('Вся ${r.name}'),
            subtitle: const Text('По всем крупным пунктам из списка'),
            onTap: () {
              Navigator.of(context).pop(
                KazOutcomeRegion(regionId: r.id, localityName: null),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        ...r.settlements.map(
          (name) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Material(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(14),
              child: ListTile(
                leading: Icon(
                  Icons.location_city_rounded,
                  color: theme.colorScheme.primary,
                ),
                title: Text(name),
                onTap: () {
                  Navigator.of(context).pop(
                    KazOutcomeRegion(regionId: r.id, localityName: name),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Собирает [SearchFilters] из результата листа (без побочных эффектов).
SearchFilters mergeLocationOutcome(SearchFilters current, KazakhstanLocationOutcome outcome) {
  return switch (outcome) {
    KazOutcomeWholeCountry() => current.copyWith(
        clearCity: true,
        clearKzLocation: true,
        clearNearby: true,
      ),
    KazOutcomeNearby(:final latitude, :final longitude, :final radiusKm) =>
      current.copyWith(
        clearCity: true,
        clearKzLocation: true,
        radiusKm: radiusKm,
        centerLatitude: latitude,
        centerLongitude: longitude,
      ),
    KazOutcomeRegion(:final regionId, :final localityName) => current.copyWith(
        clearCity: true,
        clearNearby: true,
        kzRegionId: regionId,
        kzLocalityName: localityName,
      ),
    KazOutcomeManualCity(:final city) => current.copyWith(
        clearKzLocation: true,
        clearNearby: true,
        city: city.isEmpty ? null : city,
        clearCity: city.isEmpty,
      ),
  };
}
