import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/artist_application.dart';

/// Erreur de candidature, porteuse d'un message affichable tel quel.
///
/// Traduit les codes HTTP renvoyés par l'Edge Function `verify-artist` en
/// messages français, sans jamais exposer le détail technique brut au
/// candidat (voir `logError`).
class ArtistApplicationException implements Exception {
  const ArtistApplicationException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Contrat d'accès aux candidatures artiste.
///
/// L'abstraction sert de couture de test : les tests injectent un faux
/// repository plutôt que de simuler un client Supabase.
abstract class ArtistApplicationRepository {
  /// La candidature la plus récente du candidat courant, ou `null` s'il n'en
  /// a jamais déposé.
  ///
  /// Le `select` liste explicitement les colonnes lisibles : un `select('*')`
  /// échouerait (42501), `ai_score`/`ai_analysis`/`id_document_path`/
  /// `reviewed_by` étant bloqués par des droits de colonne.
  Future<ArtistApplication?> fetchMine();

  /// Téléverse la pièce d'identité dans le bucket privé `identity-docs`, au
  /// chemin `<uid>/id-<horodatage>.<ext>` (le préfixe doit être l'uid : c'est
  /// la politique RLS du bucket). Renvoie le chemin de stockage.
  Future<String> uploadIdDocument({
    required String userId,
    required Uint8List bytes,
    required String fileExtension,
    required String contentType,
  });

  /// Envoie la candidature à l'Edge Function `verify-artist`, qui crée la
  /// ligne et approuve automatiquement (Phase 7 : sans pièce d'identité).
  ///
  /// Lève [ArtistApplicationException] avec un message français adapté au
  /// code d'erreur renvoyé.
  Future<void> submit({
    required String stageName,
    required List<String> links,
    required String statement,
    String? documentPath,
  });

  /// Annule la candidature ouverte du candidat courant — seule transition
  /// permise côté client (`pending|manual_review` → `rejected`).
  Future<void> cancelMine(String applicationId);
}

/// Implémentation Supabase de [ArtistApplicationRepository].
class SupabaseArtistApplicationRepository
    implements ArtistApplicationRepository {
  SupabaseArtistApplicationRepository(this._client);

  final SupabaseClient _client;

  static const String _table = 'artist_applications';
  static const String _bucket = 'identity-docs';

  /// Colonnes lisibles par le candidat, alignées sur les grants SQL.
  static const String _selectOwn =
      'id, user_id, stage_name, links, statement, status, '
      'decision_reason, created_at, decided_at, document_purged_at';

  @override
  Future<ArtistApplication?> fetchMine() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    final row = await _client
        .from(_table)
        .select(_selectOwn)
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (row == null) return null;
    return ArtistApplication.fromJson(row);
  }

  @override
  Future<String> uploadIdDocument({
    required String userId,
    required Uint8List bytes,
    required String fileExtension,
    required String contentType,
  }) async {
    final path =
        '$userId/id-${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
    await _client.storage
        .from(_bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    return path;
  }

  @override
  Future<void> submit({
    required String stageName,
    required List<String> links,
    required String statement,
    String? documentPath,
  }) async {
    try {
      await _client.functions.invoke(
        'verify-artist',
        body: {
          'stageName': stageName,
          'links': links,
          'statement': statement,
          'consent': true,
        },
      );
    } on FunctionException catch (e) {
      throw ArtistApplicationException(_messageFor(e));
    }
  }

  @override
  Future<void> cancelMine(String applicationId) async {
    await _client
        .from(_table)
        .update({'status': 'rejected'})
        .eq('id', applicationId);
  }

  /// Traduit la réponse d'erreur de `verify-artist` en message français.
  ///
  /// La fonction distingue déjà « déjà artiste » et « candidature en cours »
  /// dans le corps JSON (`{ "error": "..." }`) : on le reprend tel quel pour
  /// ces deux cas plutôt que de généraliser sur le seul code 409, qui les
  /// confondrait.
  String _messageFor(FunctionException e) {
    final details = e.details;
    final serverMessage = details is Map && details['error'] is String
        ? details['error'] as String
        : null;

    switch (e.status) {
      case 409:
        return serverMessage ??
            'Tu es déjà artiste, ou une candidature est déjà en cours.';
      case 429:
        return 'Une seule candidature par semaine. Réessaie plus tard.';
      case 400:
        return 'Formulaire incomplet ou invalide.';
      case 401:
        return 'Session expirée. Reconnecte-toi puis réessaie.';
      default:
        return 'La candidature n\'a pas pu être envoyée. Réessaie.';
    }
  }
}
