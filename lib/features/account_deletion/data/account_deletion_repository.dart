import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/account_deletion/domain/account_deletion.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/porty_edge_client.dart';

/// Habla con la edge function `delete-account`. Devuelve `null` si borró y
/// la falla tipada si no; nunca tira.
class AccountDeletionRepository {
  AccountDeletionRepository({PortyEdgeClient? edge})
    : _edge = edge ?? PortyEdgeClient(dio: _createDio());

  final PortyEdgeClient _edge;

  static Dio _createDio() => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      // El servidor tiene un presupuesto de 45 s (SnapTrade + RevenueCat).
      receiveTimeout: const Duration(seconds: 60),
      validateStatus: (status) => status != null && status < 600,
    ),
  );

  /// [appleAuthorizationCode]: código de un uso de Apple para que el
  /// servidor revoque el acceso de Porty a la cuenta de Apple.
  Future<AccountDeletionFailure?> deleteAccount({
    String? appleAuthorizationCode,
  }) async {
    final response = await _edge.post('delete-account', {
      'confirm': true,
      if (appleAuthorizationCode != null)
        'apple_authorization_code': appleAuthorizationCode,
    });
    if (response.statusCode == 401) return const DeletionSessionExpired();
    if (response.ok && response.body?['deleted'] == true) return null;

    // Sin respuesta o sin body que lo aclare no sabemos qué quedó hecho.
    final error = response.body?['error'];
    if (error is Map && error['nothingDeleted'] == true) {
      return const DeletionNothingDeleted();
    }
    return const DeletionPartial();
  }
}

final accountDeletionRepositoryProvider = Provider<AccountDeletionRepository>(
  (ref) => AccountDeletionRepository(),
);
