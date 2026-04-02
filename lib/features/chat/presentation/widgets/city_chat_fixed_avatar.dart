import 'package:flutter/material.dart';

import '../../domain/temirtau_city_group_config.dart';

/// Аватар официального городского чата — всегда из [TemirtauCityGroupConfig.fixedAvatarAsset].
class CityChatFixedAvatar extends StatelessWidget {
  const CityChatFixedAvatar({
    super.key,
    required this.radius,
  });

  final double radius;

  @override
  Widget build(BuildContext context) {
    final d = radius * 2;
    return ClipOval(
      child: SizedBox(
        width: d,
        height: d,
        child: Image.asset(
          TemirtauCityGroupConfig.fixedAvatarAsset,
          fit: BoxFit.cover,
          alignment: const Alignment(0, -0.15),
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, error, stackTrace) => CircleAvatar(
            radius: radius,
            backgroundColor: const Color(0xFF0284C7),
            child: Icon(
              Icons.location_city_rounded,
              color: Colors.white,
              size: radius * 1.1,
            ),
          ),
        ),
      ),
    );
  }
}
