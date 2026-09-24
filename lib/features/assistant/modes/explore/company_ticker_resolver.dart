import 'package:portfolio_assistant/domain/entities/symbol_search_result.dart';
import 'package:portfolio_assistant/domain/repositories/symbol_search_repository.dart';
import 'package:portfolio_assistant/infraestructure/repositories/finnhub_symbol_search_repository_impl.dart';

/// `resolved`: un único match claro. `ambiguous`: 2+ matches, ninguno
/// dominante — el caller debe preguntar, no adivinar. `notFound`: sin
/// matches, o falló la consulta (mismo tratamiento que "no hay match": no
/// hay suficiente info para resolver un ticker, no es un error que bloquee
/// el turno).
class CompanyTickerResolution {
  const CompanyTickerResolution.resolved(this.ticker) : matches = null;

  const CompanyTickerResolution.ambiguous(this.matches) : ticker = null;

  const CompanyTickerResolution.notFound() : ticker = null, matches = null;

  final String? ticker;
  final List<SymbolSearchResult>? matches;
}

/// Resuelve un candidato de nombre de compañía en texto libre (ej. "Apple")
/// a un ticker, vía Finnhub `/search`. La regla de "único vs. ambiguo" es
/// una decisión de producto, no de la fuente de datos — por eso vive acá y
/// no en el repositorio, que se queda como un wrapper tonto de Finnhub.
class CompanyTickerResolver {
  CompanyTickerResolver({SymbolSearchRepository? repository})
    : _repository = repository ?? FinnhubSymbolSearchRepositoryImpl();

  final SymbolSearchRepository _repository;

  /// Filtra primero a listados primarios de acciones comunes (descarta
  /// duplicados de otras plazas, ej. "BRK.A" además de "BRK-A"/"BRK.B") —
  /// si ese filtro da exactamente 1 resultado, está resuelto. 2+ (hasta 4,
  /// para no saturar la pregunta de aclaración) es ambiguo. Si el filtro no
  /// deja nada, se aplica la misma regla sobre el pool completo sin filtrar.
  Future<CompanyTickerResolution> resolve(String candidate) async {
    final result = await _repository.search(candidate);
    return result.fold((_) => const CompanyTickerResolution.notFound(), (
      matches,
    ) {
      final commonStock =
          matches
              .where((m) => m.type == 'Common Stock' && !m.symbol.contains('.'))
              .toList();
      final pool = commonStock.isNotEmpty ? commonStock : matches;

      if (pool.isEmpty) return const CompanyTickerResolution.notFound();
      if (pool.length == 1) {
        return CompanyTickerResolution.resolved(pool.first.symbol);
      }
      return CompanyTickerResolution.ambiguous(pool.take(4).toList());
    });
  }
}
