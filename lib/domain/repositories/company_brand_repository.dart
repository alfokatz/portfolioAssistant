import 'package:portfolio_assistant/domain/entities/company_brand.dart';

abstract class CompanyBrandRepository {
  /// Nunca lanza. `null` = no se pudo resolver (sin key, red, sin perfil).
  Future<CompanyBrand?> getBrand(String ticker);
}
