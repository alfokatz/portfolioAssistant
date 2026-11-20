import 'package:hive/hive.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/data_sources/closed_position_local_data_source.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/infraestructure/models/closed_position_model.dart';

class ClosedPositionLocalDataSourceImpl implements ClosedPositionLocalDataSource {
  final Box<ClosedPositionModel> box;

  ClosedPositionLocalDataSourceImpl({required this.box});

  @override
  Future<List<ClosedPosition>> getAll() async {
    return box.values.map((model) => model.toEntity()).toList()
      ..sort((a, b) => b.closeDate.compareTo(a.closeDate));
  }

  @override
  Future<void> save(ClosedPosition position) async {
    await box.put(
      position.id,
      ClosedPositionModel.fromEntity(position),
    );
  }
}

final closedPositionsBoxProvider = Provider<Box<ClosedPositionModel>>((ref) {
  throw UnimplementedError(
    'closedPositionsBoxProvider must be overridden in main',
  );
});

final closedPositionLocalDataSourceProvider =
    Provider<ClosedPositionLocalDataSource>(
  (ref) => ClosedPositionLocalDataSourceImpl(
    box: ref.watch(closedPositionsBoxProvider),
  ),
);
