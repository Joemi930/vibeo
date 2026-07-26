import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/skeleton_box.dart';
import '../../../core/widgets/vibeo_app_bar.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../profile/presentation/providers/profile_providers.dart';
import 'providers/account_providers.dart';
import 'widgets/delete_account_section.dart';
import 'widgets/email_section.dart';
import 'widgets/identity_section.dart';
import 'widgets/password_section.dart';
import 'widgets/screen_name_section.dart';

/// Écran « Compte et confidentialité » : identité civile, nom de scène et
/// nom d'utilisateur, email, mot de passe, suppression de compte.
///
/// Regroupe toutes les actions sensibles sur l'identité d'un utilisateur — la
/// zone de danger (suppression) est un cas à part traité par
/// [DeleteAccountSection], avec une confirmation qui exige de saisir le nom
/// d'utilisateur.
class AccountPrivacyScreen extends ConsumerWidget {
  const AccountPrivacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentProfileProvider);
    final identityAsync = ref.watch(currentIdentityProvider);
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: const VibeoAppBar(title: 'Compte et confidentialité'),
      body: profileAsync.when(
        loading: () => const _AccountPrivacySkeleton(),
        error: (_, _) => Center(
          child: ErrorState(
            message: 'Impossible de charger ton profil.',
            onRetry: () => ref.invalidate(currentProfileProvider),
          ),
        ),
        data: (profile) {
          if (profile == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Profil indisponible pour le moment.'),
              ),
            );
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  IdentitySection(
                    userId: profile.id,
                    identity: identityAsync.asData?.value,
                  ),
                  const SizedBox(height: 16),
                  ScreenNameSection(profile: profile),
                  const SizedBox(height: 16),
                  EmailSection(currentEmail: user?.email),
                  const SizedBox(height: 16),
                  const PasswordSection(),
                  const SizedBox(height: 28),
                  DeleteAccountSection(username: profile.username),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AccountPrivacySkeleton extends StatelessWidget {
  const _AccountPrivacySkeleton();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            SizedBox(width: double.infinity, child: SkeletonBox(height: 220)),
            SizedBox(height: 16),
            SizedBox(width: double.infinity, child: SkeletonBox(height: 140)),
            SizedBox(height: 16),
            SizedBox(width: double.infinity, child: SkeletonBox(height: 120)),
          ],
        ),
      ),
    );
  }
}
