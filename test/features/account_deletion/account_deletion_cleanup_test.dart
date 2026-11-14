// Al borrar la cuenta se borra del teléfono lo que era de ella (cómo estaba
// vestido Porty): una cuenta nueva no hereda nada. Solo si el borrado salió.
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/account_deletion/data/account_deletion_repository.dart';
import 'package:portfolio_assistant/features/account_deletion/data/subscription_store_probe.dart';
import 'package:portfolio_assistant/features/account_deletion/domain/account_deletion.dart';
import 'package:portfolio_assistant/features/account_deletion/providers/account_deletion_provider.dart';

class _Repo implements AccountDeletionRepository {
  _Repo(this.failure);

  final AccountDeletionFailure? failure;

  @override
  Future<AccountDeletionFailure?> deleteAccount({
    String? appleAuthorizationCode,
  }) async => failure;
}

class _Probe implements SubscriptionStoreProbe {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('deleted: the local cleanup runs', () async {
    var cleaned = 0;
    final ok =
        await AccountDeletionNotifier(
          repository: _Repo(null),
          probe: _Probe(),
          onDeleted: () async => cleaned++,
        ).delete();
    expect(ok, isTrue);
    expect(cleaned, 1);
  });

  test('a failed deletion keeps everything; a failing cleanup never blocks '
      'the deletion', () async {
    var cleaned = 0;
    final failed =
        await AccountDeletionNotifier(
          repository: _Repo(const DeletionNothingDeleted()),
          probe: _Probe(),
          onDeleted: () async => cleaned++,
        ).delete();
    expect(failed, isFalse);
    expect(cleaned, 0);

    final ok =
        await AccountDeletionNotifier(
          repository: _Repo(null),
          probe: _Probe(),
          onDeleted: () async => throw StateError('prefs'),
        ).delete();
    expect(ok, isTrue);
  });
}
