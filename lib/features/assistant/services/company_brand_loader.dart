import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/company_brand.dart';
import 'package:portfolio_assistant/domain/repositories/company_brand_repository.dart';
import 'package:portfolio_assistant/infraestructure/repositories/finnhub_company_brand_repository_impl.dart';

/// Resuelve nombre + logo de un ticker para las cards del catálogo, del
/// lado del cliente — el modelo nunca paga tokens por esto.
///
/// Cachea por la vida de la app (un logo no cambia) incluyendo los
/// negativos, y deduplica requests en vuelo: una respuesta con cinco cards
/// del mismo ticker hace UN solo request. La key de Finnhub es compartida
/// (60 req/min), por eso el cache es agresivo.
class CompanyBrandLoader {
  CompanyBrandLoader(this._repository);

  final CompanyBrandRepository _repository;
  final _cache = <String, CompanyBrand>{};
  final _inFlight = <String, Future<CompanyBrand>>{};

  /// Valor ya resuelto, si lo hay — permite pintar el logo en el primer
  /// frame cuando el ticker ya apareció antes en la conversación.
  CompanyBrand? peek(String ticker) => _cache[ticker.toUpperCase()];

  Future<CompanyBrand> load(String ticker) {
    final key = ticker.toUpperCase();
    final cached = _cache[key];
    if (cached != null) return Future.value(cached);
    return _inFlight.putIfAbsent(key, () async {
      final brand = await _repository.getBrand(key);
      final resolved = brand ?? CompanyBrand(ticker: key);
      // Una falla transitoria (brand == null) no se cachea: el próximo
      // widget del mismo ticker lo vuelve a intentar.
      if (brand != null) _cache[key] = resolved;
      _inFlight.remove(key);
      return resolved;
    });
  }
}

final companyBrandLoaderProvider = Provider<CompanyBrandLoader>(
  (ref) => CompanyBrandLoader(FinnhubCompanyBrandRepositoryImpl()),
);
