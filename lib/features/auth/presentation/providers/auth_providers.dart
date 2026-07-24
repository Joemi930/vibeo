import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/supabase/supabase_providers.dart';
import '../../data/auth_repository.dart';

/// Fournit le [AuthRepository] concret (surchargeable en test).
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return SupabaseAuthRepository(ref.watch(supabaseClientProvider));
});

/// Flux brut des changements d'état d'authentification Supabase.
final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authRepositoryProvider).onAuthStateChange;
});

/// Utilisateur courant (null si déconnecté). Réagit aux changements de session.
final currentUserProvider = Provider<User?>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  // Se recalcule à chaque événement d'auth.
  ref.watch(authStateChangesProvider);
  return repo.currentUser;
});

/// Vrai si un utilisateur est connecté (utilisé par la garde du router).
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(currentUserProvider) != null;
});
