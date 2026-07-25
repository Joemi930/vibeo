import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/profile/presentation/providers/profile_providers.dart';
import '../theme/app_colors.dart';

/// Avatar rond d'un utilisateur.
///
/// Le bucket `avatars` étant privé, le chemin de stockage est résolu en URL
/// signée via [avatarSignedUrlProvider]. En l'absence d'image, on retombe sur
/// les initiales sur fond dégradé — jamais un trou visuel.
class AvatarCircle extends ConsumerWidget {
  const AvatarCircle({
    required this.name,
    this.avatarPath,
    this.radius = 20,
    super.key,
  });

  final String name;
  final String? avatarPath;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(avatarSignedUrlProvider(avatarPath)).asData?.value;

    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: VibeoColors.of(context).gradient,
      ),
      clipBehavior: Clip.antiAlias,
      child: url == null
          ? Center(
              child: Text(
                _initials(name),
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: radius * 0.7,
                ),
              ),
            )
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Center(
                child: Text(
                  _initials(name),
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: radius * 0.7,
                  ),
                ),
              ),
            ),
    );
  }

  /// Une ou deux initiales, à partir du nom affiché.
  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'))
      ..removeWhere((p) => p.isEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.characters.first.toUpperCase();
    }
    return (parts.first.characters.first + parts[1].characters.first)
        .toUpperCase();
  }
}
