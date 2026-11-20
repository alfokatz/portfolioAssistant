// Datos de ejemplo para los tests de la prosa del brief (prompt, validador y
// generador): el bundle de `test/fixtures/daily_brief/` más números de la
// Home armados a mano. Sin red ni modelo.
import 'dart:convert';
import 'dart:io';

import 'package:portfolio_assistant/domain/utils/portfolio_day_move.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_bundle.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_input.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_numbers.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_writer.dart';

DailyBriefBundle fixtureBundle([String name = 'bundle_brief_full']) =>
    DailyBriefBundle.parse(
      (jsonDecode(
                File('test/fixtures/daily_brief/$name.json').readAsStringSync(),
              )
              as Map)
          .cast<String, Object?>(),
    );

/// NVDA sube fuerte (con 2 titulares), AAPL baja un poco (con 1) y VOO casi
/// no se mueve (sin titular).
DailyBriefNumbers fixtureNumbers() => DailyBriefNumbers(
  period: DayMovePeriod.lastClose,
  asOfDay: DateTime(2026, 12, 1),
  abs: 312.4,
  pct: 0.82,
  movers: const [
    BriefMover(ticker: 'NVDA', pct: 4.1, contributionAbs: 220, weightPct: 18.2),
    BriefMover(ticker: 'AAPL', pct: -1.2, contributionAbs: -60, weightPct: 12),
    BriefMover(ticker: 'VOO', pct: 0.02, contributionAbs: 5, weightPct: 30),
  ],
);

/// Un titular de la watchlist (solo Gold) que el bundle de Premium no trae.
const watchHeadline = BriefHeadline(
  id: 'h5',
  ticker: 'MELI',
  watch: true,
  title: 'MercadoLibre abre un nuevo centro logístico',
  source: 'Reuters',
  domain: 'reuters.com',
  url: 'https://www.reuters.com/business/meli-logistics-2026-12-01/',
);

/// Un titular de cartera de una posición que no movió el día (no tiene "por
/// qué": va como noticia). Trae una cifra, que está respaldada.
const heldHeadline = BriefHeadline(
  id: 'h4',
  ticker: 'MSFT',
  watch: false,
  title: 'Microsoft invertirá 10 mil millones en centros de datos',
  source: 'AP',
  domain: 'apnews.com',
  url: 'https://apnews.com/article/microsoft-data-centers-2026',
);

DailyBriefInput fixtureInput({
  String language = 'es',
  bool withWatch = false,
  bool withExtraHeld = false,
  Set<String> assetClasses = const {'equity', 'bond'},
  DailyBriefBundle? bundle,
}) {
  final b = bundle ?? fixtureBundle();
  return DailyBriefInput(
    language: language,
    numbers: fixtureNumbers(),
    held: [...b.held, if (withExtraHeld) heldHeadline],
    watch: [if (withWatch) watchHeadline],
    market: b.market,
    assetClasses: assetClasses,
  );
}

DailyBriefWritingRequest fixtureRequest({
  String language = 'es',
  DailyBriefBundle? bundle,
}) {
  final b = bundle ?? fixtureBundle();
  return DailyBriefWritingRequest(
    day: '2026-12-02',
    language: language,
    numbers: fixtureNumbers(),
    held: b.held,
    watch: b.watch,
    market: b.market,
    assetClasses: b.assetClasses,
  );
}

/// Un borrador del modelo, como JSON (la forma del esquema).
Map<String, Object?> goodDraftJson() => {
  'why': [
    {
      'news_id': 'h1',
      'text': 'Subió bastante el día que la empresa presentó resultados.',
    },
    {
      'news_id': 'h3',
      'text': 'Bajó un poco el día que presentó una nueva línea de productos.',
    },
  ],
  'held_news': <Object?>[],
  'watch_news': <Object?>[],
  'market': [
    {
      'topic_id': 'bonds_rates',
      'connection':
          'Tenés bonos o ETF de renta fija, que se mueven con las tasas.',
    },
  ],
};
