import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_providers.dart';
import '../../../../core/utils/dev_log.dart';
import '../../data/artist_application_repository.dart';
import '../../domain/artist_application.dart';

final artistApplicationRepositoryProvider =
    Provider<ArtistApplicationRepository>((ref) {
      return SupabaseArtistApplicationRepository(
        ref.watch(supabaseClientProvider),
      );
    });

/// La candidature la plus récente du candidat courant (null s'il n'en a
/// jamais déposé). Alimente à la fois la redirection de `/become-artist` et
/// l'écran de suivi.
final myApplicationProvider = FutureProvider<ArtistApplication?>((ref) {
  return ref.watch(artistApplicationRepositoryProvider).fetchMine();
});

/// Envoi de candidature et annulation, avec état de chargement immuable.
@immutable
class SubmitApplicationState {
  const SubmitApplicationState({this.isSubmitting = false, this.error});

  final bool isSubmitting;
  final String? error;

  SubmitApplicationState copyWith({
    bool? isSubmitting,
    String? error,
    bool clearError = false,
  }) {
    return SubmitApplicationState(
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class ArtistApplicationController extends Notifier<SubmitApplicationState> {
  @override
  SubmitApplicationState build() => const SubmitApplicationState();

  /// Téléverse le document puis envoie la candidature. Renvoie `true` en cas
  /// de succès.
  Future<bool> submit({
    required String userId,
    required String stageName,
    required List<String> links,
    required String statement,
    required Uint8List documentBytes,
    required String documentExtension,
    required String documentContentType,
  }) async {
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final repo = ref.read(artistApplicationRepositoryProvider);
      final documentPath = await repo.uploadIdDocument(
        userId: userId,
        bytes: documentBytes,
        fileExtension: documentExtension,
        contentType: documentContentType,
      );
      await repo.submit(
        stageName: stageName,
        links: links,
        statement: statement,
        documentPath: documentPath,
      );
      ref.invalidate(myApplicationProvider);
      state = state.copyWith(isSubmitting: false);
      return true;
    } on ArtistApplicationException catch (e) {
      state = state.copyWith(isSubmitting: false, error: e.message);
      return false;
    } catch (error, stack) {
      logError('envoi de candidature impossible', error, stack);
      state = state.copyWith(
        isSubmitting: false,
        error: 'La candidature n\'a pas pu être envoyée. Réessaie.',
      );
      return false;
    }
  }

  /// Annule la candidature ouverte du candidat courant.
  Future<bool> cancel(String applicationId) async {
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      await ref
          .read(artistApplicationRepositoryProvider)
          .cancelMine(applicationId);
      ref.invalidate(myApplicationProvider);
      state = state.copyWith(isSubmitting: false);
      return true;
    } catch (error, stack) {
      logError('annulation de candidature impossible', error, stack);
      state = state.copyWith(
        isSubmitting: false,
        error: 'L\'annulation a échoué. Réessaie.',
      );
      return false;
    }
  }
}

final artistApplicationControllerProvider =
    NotifierProvider<ArtistApplicationController, SubmitApplicationState>(
      ArtistApplicationController.new,
    );
