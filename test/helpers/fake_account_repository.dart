import 'package:vibeo/features/settings/data/account_repository.dart';
import 'package:vibeo/features/settings/domain/legal_identity.dart';

/// Implémentation de test de [AccountRepository] : aucun appel réseau,
/// comportement configurable pour piloter les scénarios de test.
class FakeAccountRepository implements AccountRepository {
  FakeAccountRepository({this.throwUsernameTaken = false});

  /// Si vrai, [updateScreenName] lève [UsernameTakenException].
  final bool throwUsernameTaken;

  LegalIdentity? identity;

  // Journal d'appels pour les assertions de test.
  final List<String> calls = [];

  @override
  Future<LegalIdentity?> fetchIdentity(String userId) async => identity;

  @override
  Future<LegalIdentity> saveIdentity({
    required String userId,
    required String legalFirstName,
    required String legalLastName,
    String? legalMiddleName,
  }) async {
    calls.add('saveIdentity:$userId');
    identity = LegalIdentity(
      userId: userId,
      legalFirstName: legalFirstName,
      legalLastName: legalLastName,
      legalMiddleName: legalMiddleName,
    );
    return identity!;
  }

  @override
  Future<void> updateScreenName({
    required String userId,
    required String? displayName,
    required String username,
  }) async {
    calls.add('updateScreenName:$userId:$username');
    if (throwUsernameTaken) throw const UsernameTakenException();
  }

  @override
  Future<String> uploadBanner({
    required String userId,
    required List<int> bytes,
    required String fileExtension,
    required String contentType,
  }) async {
    calls.add('uploadBanner:$userId');
    return '$userId/banner.$fileExtension';
  }

  @override
  Future<void> updateEmail(String newEmail) async {
    calls.add('updateEmail:$newEmail');
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    calls.add('updatePassword');
  }

  @override
  Future<void> deleteAccount() async {
    calls.add('deleteAccount');
  }
}
