import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/utils/dev_log.dart';
import '../../../core/widgets/verified_badge.dart';
import '../../../core/widgets/vibeo_app_bar.dart';
import '../../auth/domain/profile.dart';
import '../../auth/domain/user_role.dart';
import '../../upload/data/thumbnail_picker.dart';
import '../../upload/data/video_picker.dart' show PickerException;
import 'providers/profile_providers.dart';
import 'widgets/banner_editor.dart';

/// Écran Profil : affichage et édition (nom affiché, bio, avatar).
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentProfileProvider);

    ref.listen(navigationPopSignalProvider, (_, _) {
      ref.invalidate(currentProfileProvider);
    });

    return Scaffold(
      appBar: VibeoAppBar(
        title: 'Profil',
        actions: [
          IconButton(
            tooltip: 'Paramètres',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push(AppRoutes.settings),
          ),
        ],
      ),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            _ErrorView(onRetry: () => ref.invalidate(currentProfileProvider)),
        data: (profile) {
          if (profile == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Profil indisponible pour le moment.'),
              ),
            );
          }
          return _ProfileView(profile: profile);
        },
      ),
    );
  }
}

class _ProfileView extends ConsumerWidget {
  const _ProfileView({required this.profile});
  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final avatarAsync = ref.watch(avatarSignedUrlProvider(profile.avatarUrl));

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(16),
              ),
              child: BannerEditor(profile: profile),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(
                children: [
                  Center(
                    child: _AvatarEditor(
                      profile: profile,
                      imageUrl: avatarAsync.asData?.value,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          profile.resolvedName,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (profile.isArtist) ...[
                        const SizedBox(width: 6),
                        const VerifiedBadge(size: 20),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      '@${profile.username}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Center(child: _RoleBadge(role: profile.role)),
                  const SizedBox(height: 24),
                  _InfoCard(
                    title: 'Bio',
                    child: Text(
                      (profile.bio == null || profile.bio!.trim().isEmpty)
                          ? 'Aucune bio pour le moment.'
                          : profile.bio!,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => _openEditSheet(context, ref),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Modifier le profil'),
                  ),
                  const SizedBox(height: 12),
                  // Un artiste est un utilisateur comme les autres : sa seule
                  // différence est l'accès au Studio (statistiques,
                  // publication, suppression de ses clips).
                  if (profile.isArtist)
                    OutlinedButton.icon(
                      onPressed: () => context.push(AppRoutes.studio),
                      icon: const Icon(Icons.video_settings_rounded),
                      label: const Text('Ouvrir le Studio'),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: () => context.push(AppRoutes.becomeArtist),
                      icon: const Icon(Icons.verified_outlined),
                      label: const Text('Devenir artiste'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEditSheet(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditProfileSheet(profile: profile),
    );
  }
}

class _AvatarEditor extends ConsumerWidget {
  const _AvatarEditor({required this.profile, required this.imageUrl});
  final Profile profile;
  final String? imageUrl;

  Future<void> _pickAndUpload(BuildContext context, WidgetRef ref) async {
    try {
      // Passe par `pickThumbnailImage` : détection du type MIME par
      // extension réelle (pas de devinette qui enverrait, par exemple, un
      // `.gif` en `image/jpeg`) et vérification de taille alignée sur le
      // plafond Storage, au lieu de dupliquer cette logique ici.
      final picked = await pickThumbnailImage(maxWidth: 1024);
      if (picked == null) return;
      final ok = await ref
          .read(profileControllerProvider.notifier)
          .uploadAvatar(
            userId: profile.id,
            bytes: picked.bytes,
            fileExtension: picked.fileExtension,
            contentType: picked.contentType,
          );
      if (context.mounted && !ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Échec du téléversement de l\'avatar.')),
        );
      }
    } on PickerException catch (e) {
      logError('ProfileScreen', e);
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
    final uploading = ref.watch(profileControllerProvider).isLoading;
    return Stack(
      children: [
        CircleAvatar(
          radius: 52,
          backgroundColor: theme.colorScheme.surfaceContainerHigh,
          backgroundImage: imageUrl != null ? NetworkImage(imageUrl!) : null,
          child: imageUrl == null
              ? Text(
                  _initials(profile.resolvedName),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                )
              : null,
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: Material(
            color: theme.colorScheme.primary,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: uploading ? null : () => _pickAndUpload(context, ref),
              child: Padding(
                padding: const EdgeInsets.all(7),
                child: uploading
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            theme.colorScheme.onPrimary,
                          ),
                        ),
                      )
                    : Icon(
                        Icons.photo_camera_rounded,
                        size: 16,
                        color: theme.colorScheme.onPrimary,
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.characters.take(2).toString().toUpperCase();
    }
    return (parts.first.characters.take(1).toString() +
            parts[1].characters.take(1).toString())
        .toUpperCase();
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});
  final UserRole role;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, icon) = switch (role) {
      UserRole.artist => ('Artiste vérifié', Icons.verified_rounded),
      UserRole.admin => ('Admin', Icons.shield_rounded),
      UserRole.listener => ('Auditeur', Icons.headphones_rounded),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onPrimaryContainer),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _EditProfileSheet extends ConsumerStatefulWidget {
  const _EditProfileSheet({required this.profile});
  final Profile profile;

  @override
  ConsumerState<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl = TextEditingController(
    text: widget.profile.displayName ?? '',
  );
  late final TextEditingController _bioCtrl = TextEditingController(
    text: widget.profile.bio ?? '',
  );

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await ref
        .read(profileControllerProvider.notifier)
        .save(
          userId: widget.profile.id,
          displayName: _nameCtrl.text.trim(),
          bio: _bioCtrl.text.trim(),
        );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Échec de l\'enregistrement.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final saving = ref.watch(profileControllerProvider).isLoading;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Modifier le profil',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Nom affiché'),
              maxLength: 50,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _bioCtrl,
              decoration: const InputDecoration(labelText: 'Bio'),
              maxLength: 500,
              maxLines: 4,
              validator: (v) {
                if ((v ?? '').length > 500) return '500 caractères maximum.';
                return null;
              },
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: saving ? null : _save,
              child: saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 12),
            const Text('Impossible de charger le profil.'),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Réessayer')),
          ],
        ),
      ),
    );
  }
}
