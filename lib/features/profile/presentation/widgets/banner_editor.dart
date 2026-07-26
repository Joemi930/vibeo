import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/dev_log.dart';
import '../../../auth/domain/profile.dart';
import '../../../settings/presentation/providers/account_providers.dart';
import '../../../upload/data/thumbnail_picker.dart';
import '../../../upload/data/video_picker.dart' show PickerException;
import '../providers/profile_providers.dart';

/// Bannière de profil modifiable : image si `banner_path` est renseigné,
/// dégradé de repli sinon (jamais de trou visuel). Un bouton flottant permet
/// de choisir une nouvelle image depuis la galerie.
///
/// Réutilisée en lecture seule (sans le bouton d'édition) sur la page
/// publique d'un artiste (`artist_screen.dart`).
class BannerEditor extends ConsumerWidget {
  const BannerEditor({
    required this.profile,
    this.height = 150,
    this.editable = true,
    super.key,
  });

  final Profile profile;
  final double height;

  /// `false` sur la page publique d'un artiste : personne d'autre que le
  /// propriétaire ne doit pouvoir modifier sa bannière.
  final bool editable;

  /// Une bannière est plus large qu'un avatar mais reste une simple image de
  /// couverture : un plafond de 4 Mo (au-dessus du plafond avatar/miniature
  /// de 2 Mo) suffit largement sans peser sur le quota Storage gratuit.
  static const int _maxBannerBytes = 4 * 1024 * 1024;

  Future<void> _pickAndUpload(BuildContext context, WidgetRef ref) async {
    try {
      final picked = await pickThumbnailImage(
        maxWidth: 1600,
        maxBytes: _maxBannerBytes,
      );
      if (picked == null) return;
      final ok = await ref
          .read(accountControllerProvider.notifier)
          .uploadBanner(
            userId: profile.id,
            bytes: picked.bytes,
            fileExtension: picked.fileExtension,
            contentType: picked.contentType,
          );
      if (context.mounted && !ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Échec du téléversement de la bannière.'),
          ),
        );
      }
    } on PickerException catch (e) {
      logError('BannerEditor', e);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final imageUrl = ref.watch(avatarSignedUrlProvider(profile.bannerPath));
    final uploading = editable
        ? ref.watch(accountControllerProvider).isLoading
        : false;

    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: VibeoColors.of(context).gradient,
            ),
            child: imageUrl.asData?.value == null
                ? null
                : Image.network(
                    imageUrl.asData!.value!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
          ),
          if (editable)
            Positioned(
              right: 12,
              bottom: 12,
              child: Semantics(
                button: true,
                label: 'Changer la bannière de profil',
                child: Material(
                  color: theme.colorScheme.surface.withValues(alpha: 0.9),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: uploading
                        ? null
                        : () => _pickAndUpload(context, ref),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: uploading
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  theme.colorScheme.primary,
                                ),
                              ),
                            )
                          : Icon(
                              Icons.photo_camera_rounded,
                              color: theme.colorScheme.primary,
                            ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
