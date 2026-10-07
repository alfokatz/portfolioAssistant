import 'package:portfolio_assistant/domain/entities/investor_profile.dart';

abstract class InvestorProfileRepository {
  /// `null` si el usuario todavía no completó su perfil.
  Future<InvestorProfile?> fetch();

  /// Crea o reemplaza el perfil; `updated_at` lo fija el servidor.
  Future<InvestorProfile> save({
    required RiskTolerance risk,
    required InvestmentHorizon horizon,
    required InvestmentObjective objective,
    InvestmentExperience? experience,
    DrawdownReaction? drawdownReaction,
  });
}
