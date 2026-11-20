import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/use_cases/get_closed_positions_use_case.dart';

/// Una venta por id, para el detalle cuando no llega con la venta ya
/// cargada. `null` si no existe (se borró); falla si no se pudo cargar.
final closedPositionDetailProvider = FutureProvider.autoDispose
    .family<ClosedPosition?, String>((ref, id) async {
      final result = await ref.watch(getClosedPositionsUseCaseProvider).call();
      return result.fold(
        (error) => throw error,
        (positions) => positions.where((p) => p.id == id).firstOrNull,
      );
    });
