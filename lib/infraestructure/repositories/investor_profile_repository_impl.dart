import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/investor_profile.dart';
import 'package:portfolio_assistant/domain/repositories/investor_profile_repository.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/supabase/investor_profile_supabase_data_source.dart';

class InvestorProfileRepositoryImpl implements InvestorProfileRepository {
  InvestorProfileRepositoryImpl({
    required InvestorProfileSupabaseDataSource dataSource,
  }) : _dataSource = dataSource;

  final InvestorProfileSupabaseDataSource _dataSource;

  @override
  Future<InvestorProfile?> fetch() => _dataSource.fetch();

  @override
  Future<InvestorProfile> save({
    required RiskTolerance risk,
    required InvestmentHorizon horizon,
    required InvestmentObjective objective,
  }) =>
      _dataSource.save(risk: risk, horizon: horizon, objective: objective);
}

final investorProfileRepositoryProvider = Provider<InvestorProfileRepository>(
  (ref) => InvestorProfileRepositoryImpl(
    dataSource: ref.watch(investorProfileSupabaseDataSourceProvider),
  ),
);
