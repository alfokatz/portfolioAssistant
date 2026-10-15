/// Un ítem de "qué dicen los super investors" de la semana, tal como lo arma
/// la edge function `investor-pulse` (igual para todos los usuarios).
///
/// Las noticias traen solo titular, medio y fecha: Porty las parafrasea y
/// atribuye, nunca inventa citas. Las presentaciones a la SEC son dato duro
/// (compró, vendió, pasó el 5%, presentó su cartera del trimestre).
class InvestorPulseItem {
  const InvestorPulseItem({
    required this.id,
    required this.investorId,
    required this.investorName,
    required this.isMarketVoice,
    required this.isFiling,
    required this.date,
    required this.url,
    this.organization,
    this.headline,
    this.source,
    this.form,
    this.action,
    this.issuerName,
    this.issuerTicker,
    this.shares,
    this.period,
  });

  /// `i1`, `i2`… (estables: los asigna el servidor).
  final String id;
  final String investorId;
  final String investorName;
  final String? organization;

  /// Voces del mercado (la Fed, banqueros), que la app etiqueta aparte.
  final bool isMarketVoice;
  final bool isFiling;
  final DateTime date;
  final String url;

  // Noticia
  final String? headline;
  final String? source;

  // Presentación a la SEC
  final String? form;

  /// `buy` | `sell` | `stake` | `stake_update` | `quarterly_portfolio`.
  final String? action;
  final String? issuerName;
  final String? issuerTicker;
  final double? shares;

  /// Fin del trimestre que cubre un 13F.
  final DateTime? period;

  /// `null` si al ítem le falta algo esencial (versión vieja del servidor,
  /// dato corrupto): se descarta en vez de mostrar algo a medias.
  static InvestorPulseItem? tryParse(Map<String, Object?> json) {
    final id = json['id'];
    final investorId = json['investor_id'];
    final name = json['investor_name'];
    final type = json['type'];
    final date = DateTime.tryParse('${json['date']}');
    final url = json['url'];
    if (id is! String ||
        investorId is! String ||
        name is! String ||
        (type != 'news' && type != 'filing') ||
        date == null ||
        url is! String ||
        !url.startsWith('https://')) {
      return null;
    }
    final isFiling = type == 'filing';
    final headline = json['headline'] as String?;
    if (!isFiling && (headline == null || headline.isEmpty)) return null;
    return InvestorPulseItem(
      id: id,
      investorId: investorId,
      investorName: name,
      organization: json['organization'] as String?,
      isMarketVoice: json['voice'] == 'market_voice',
      isFiling: isFiling,
      date: DateTime(date.year, date.month, date.day),
      url: url,
      headline: headline,
      source: json['source'] as String?,
      form: json['form'] as String?,
      action: json['action'] as String?,
      issuerName: json['issuer_name'] as String?,
      issuerTicker: (json['issuer_ticker'] as String?)?.toUpperCase(),
      shares: (json['shares'] as num?)?.toDouble(),
      period: DateTime.tryParse('${json['period']}'),
    );
  }
}
