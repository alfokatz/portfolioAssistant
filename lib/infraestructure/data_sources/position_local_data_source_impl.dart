import 'package:hive/hive.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/data_sources/position_local_data_source.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/infraestructure/models/position_model.dart';

class PositionLocalDataSourceImpl implements PositionLocalDataSource {
  final Box<PositionModel> box;

  PositionLocalDataSourceImpl({required this.box});

  @override
  Future<void> delete(String id) async {
    await box.delete(id);
  }

  @override
  Future<List<Position>> getAll() async {
    return box.values.map((model) => model.toEntity()).toList()
      ..sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
  }

  @override
  Future<Position?> getById(String id) async {
    final model = box.get(id);
    return model?.toEntity();
  }

  @override
  Future<void> save(Position position) async {
    await box.put(
      position.id,
      PositionModel.fromEntity(position),
    );
  }
}

final positionsBoxProvider = Provider<Box<PositionModel>>((ref) {
  throw UnimplementedError('positionsBoxProvider must be overridden in main');
});

final positionLocalDataSourceProvider = Provider<PositionLocalDataSource>(
  (ref) => PositionLocalDataSourceImpl(box: ref.watch(positionsBoxProvider)),
);
