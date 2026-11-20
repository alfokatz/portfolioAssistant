import 'package:portfolio_assistant/features/assistant/data/invest/sector_display_name.dart';
import 'package:portfolio_assistant/features/assistant/data/invest/yahoo_company_profile_client.dart';

/// Sector en español de cualquier ticker, desde su perfil real en Yahoo.
/// Sin dato → "Sin clasificar" (nunca se adivina).
abstract final class SectorResolver {
  static Map<String, String> fromProfiles(
    Iterable<String> tickers,
    Map<String, YahooCompanyProfile?> profiles,
  ) => {
    for (final ticker in tickers.map((t) => t.toUpperCase()))
      ticker: SectorDisplayName.fromRaw(profiles[ticker]?.sector),
  };
}
