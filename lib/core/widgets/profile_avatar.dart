import 'package:flutter/material.dart';

import '../../data/models.dart';

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.profile, this.radius = 24});

  final Profile? profile;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final url = p?.avatarUrl?.trim();
    return CircleAvatar(
      radius: radius,
      backgroundImage: url == null || url.isEmpty ? null : NetworkImage(url),
      child: url == null || url.isEmpty ? Icon(p?.role.icon ?? Icons.person_rounded, size: radius) : null,
    );
  }
}
