import 'package:portfolio_assistant/domain/entities/company_brand.dart';
import 'package:portfolio_assistant/domain/repositories/company_brand_repository.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/finnhub_http_client.dart';

/// Nombre + logo desde `/stock/profile2` de Finnhub. Es puramente
/// cosmético (avatar y subtítulo de las cards), así que cualquier falla se
/// traduce a `null` sin distinguir la causa.
class FinnhubCompanyBrandRepositoryImpl implements CompanyBrandRepository {
  FinnhubCompanyBrandRepositoryImpl({FinnhubHttpClient? client})
    : _client = client ?? FinnhubHttpClient();

  final FinnhubHttpClient _client;

  @override
  Future<CompanyBrand?> getBrand(String ticker) async {
    if (!_client.hasApiKey) return null;
    final upper = ticker.toUpperCase();
    try {
      final response = await _client.get(
        '/stock/profile2',
        queryParameters: {'symbol': upper},
      );
      if (response.statusCode != 200 || response.data is! Map) return null;
      final body = response.data as Map;
      if (body.isEmpty) return CompanyBrand(ticker: upper);
      return CompanyBrand(
        ticker: upper,
        name: _string(body['name']),
        logoUrl: _string(body['logo']),
      );
    } catch (_) {
      return null;
    }
  }

  static String? _string(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
