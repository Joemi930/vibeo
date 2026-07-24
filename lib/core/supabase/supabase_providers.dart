import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Expose le client Supabase déjà initialisé dans `main()` via
/// `Supabase.initialize(...)`. On passe toujours par ce provider plutôt que par
/// le singleton global, pour rester testable (surcharge possible).
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});
