import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/theme_mode_provider.dart';

/// Mode invité : consultation sans compte, à la manière de YouTube.
///
/// Un invité n'a **aucune session Supabase** — il interroge la base avec le
/// rôle Postgres `anon`, et ne voit donc que ce que les politiques RLS ouvrent
/// explicitement (clips publiés, profils publics, commentaires). Toute action
/// nécessitant un compte (aimer, commenter, s'abonner, signaler, publier) est
/// interceptée côté UI par `requireAuth`, puis refusée côté serveur par la RLS.
///
/// On n'utilise volontairement pas l'authentification anonyme de Supabase :
/// elle créerait un utilisateur et un profil bien réels pour chaque visiteur.
class GuestModeNotifier extends Notifier<bool> {
  static const String _key = 'guest_mode';

  @override
  bool build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return prefs.getBool(_key) ?? false;
  }

  /// Active le mode invité (bouton « Continuer en tant qu'invité »).
  Future<void> enable() => _set(true);

  /// Quitte le mode invité (connexion réussie ou retour volontaire à l'auth).
  Future<void> disable() => _set(false);

  Future<void> _set(bool value) async {
    state = value;
    await ref.read(sharedPreferencesProvider).setBool(_key, value);
  }
}

final guestModeProvider = NotifierProvider<GuestModeNotifier, bool>(
  GuestModeNotifier.new,
);
