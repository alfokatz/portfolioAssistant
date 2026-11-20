// Borrado de una cuenta de Apple: el código para revocar el acceso viaja a
// delete-account; cerrar la hoja de Apple cancela; si Apple falla, se borra
// igual. Correr: flutter test test/features/account_deletion
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/account_deletion/data/account_deletion_repository.dart';
import 'package:portfolio_assistant/features/account_deletion/data/subscription_store_probe.dart';
import 'package:portfolio_assistant/features/account_deletion/domain/account_deletion.dart';
import 'package:portfolio_assistant/features/account_deletion/providers/account_deletion_provider.dart';

class _Repo implements AccountDeletionRepository {
  final codes = <String?>[];

  @override
  Future<AccountDeletionFailure?> deleteAccount({
    String? appleAuthorizationCode,
  }) async {
    codes.add(appleAuthorizationCode);
    return null;
  }
}

class _Probe implements SubscriptionStoreProbe {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AccountDeletionNotifier _notifier(_Repo repo, AppleRevocation apple) =>
    AccountDeletionNotifier(repository: repo, probe: _Probe(), apple: apple);

void main() {
  test('cuenta sin Apple: no pide código y borra', () async {
    final repo = _Repo();
    var asked = 0;
    final n = _notifier(
      repo,
      AppleRevocation(
        needed: () => false,
        requestCode: () async {
          asked++;
          return 'code';
        },
      ),
    );
    expect(await n.delete(), isTrue);
    expect(asked, 0);
    expect(repo.codes, [null]);
  });

  test('cuenta con Apple: manda el código a delete-account', () async {
    final repo = _Repo();
    final n = _notifier(
      repo,
      AppleRevocation(needed: () => true, requestCode: () async => 'c-123'),
    );
    expect(await n.delete(), isTrue);
    expect(repo.codes, ['c-123']);
  });

  test('cerrar la hoja de Apple cancela el borrado sin error', () async {
    final repo = _Repo();
    final n = _notifier(
      repo,
      AppleRevocation(needed: () => true, requestCode: () async => null),
    );
    expect(await n.delete(), isFalse);
    expect(repo.codes, isEmpty);
    expect(n.state.deleting, isFalse);
    expect(n.state.failure, isNull);
  });

  test('si Apple falla, se borra igual sin código (best effort)', () async {
    final repo = _Repo();
    final n = _notifier(
      repo,
      AppleRevocation(
        needed: () => true,
        requestCode: () async => throw Exception('apple down'),
      ),
    );
    expect(await n.delete(), isTrue);
    expect(repo.codes, [null]);
  });
}
