/// Configuration d'environnement lue au moment de la compilation via
/// `--dart-define-from-file=env.json` (voir `.env.example`).
///
/// Aucune valeur secrète n'est stockée dans le code : les clés proviennent
/// exclusivement des `--dart-define`. Seule la clé publique `anon` de Supabase
/// est utilisée côté application ; la clé `service_role` ne doit JAMAIS y figurer.
class Env {
  const Env._();

  /// URL du projet Supabase (ex. https://xxxx.supabase.co).
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// Clé publique (anon / publishable) du projet Supabase.
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  /// Adresse publique du site, utilisée pour construire les liens de partage
  /// depuis Android (sur le web, l'origine réelle de la page est préférée).
  ///
  /// Sans valeur, le partage se fait sans lien plutôt qu'avec un lien mort.
  static const String webBaseUrl = String.fromEnvironment('WEB_BASE_URL');

  /// Vrai si les deux variables indispensables sont fournies.
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Message d'aide affiché si la configuration est absente.
  static const String missingConfigMessage =
      'Configuration manquante : lancez l\'app avec '
      '--dart-define-from-file=env.json (voir .env.example).';
}
