import 'dart:async';
import 'dart:typed_data';

import 'package:dartz/dartz.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/subscription/subscription_policy.dart';
import 'package:portfolio_assistant/domain/use_cases/add_position_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/close_position_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_current_price_use_case.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';
import 'package:portfolio_assistant/features/product_events/data/product_events.dart';
import 'package:portfolio_assistant/features/statement_import/data/screenshot_shrinker.dart';
import 'package:portfolio_assistant/features/statement_import/data/statement_import_client.dart';
import 'package:portfolio_assistant/features/statement_import/domain/holding_change.dart';
import 'package:portfolio_assistant/features/statement_import/domain/import_row.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';

/// Un archivo elegido por el usuario.
class PickedStatement {
  const PickedStatement({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// Abre el selector de archivos del sistema. `null` si el usuario canceló.
typedef StatementPicker = Future<PickedStatement?> Function();

Future<PickedStatement?> _pickWithSystem() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['csv', 'pdf', 'txt', 'tsv'],
    withData: true,
  );
  final file = result?.files.singleOrNull;
  final bytes = file?.bytes;
  if (file == null || bytes == null) return null;
  return PickedStatement(name: file.name, bytes: bytes);
}

final statementPickerProvider = Provider<StatementPicker>(
  (ref) => _pickWithSystem,
);

/// Una captura de la app del bróker (de la galería). Se achica antes de
/// mandarla (ver [ScreenshotShrinker]).
Future<PickedStatement?> _pickImageWithSystem() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.image,
    withData: true,
  );
  final file = result?.files.singleOrNull;
  final bytes = file?.bytes;
  if (file == null || bytes == null) return null;
  return PickedStatement(
    name: file.name,
    bytes: await ScreenshotShrinker.shrink(bytes),
  );
}

final screenshotPickerProvider = Provider<StatementPicker>(
  (ref) => _pickImageWithSystem,
);

/// Cómo trajo la cartera: un archivo, una captura o escribiéndola.
enum ImportOrigin {
  file,
  screenshot,
  note;

  /// El `method` de `portfolio_loaded`.
  String get loadMethod => switch (this) {
    ImportOrigin.file => PortfolioLoadMethod.file,
    ImportOrigin.screenshot => PortfolioLoadMethod.screenshot,
    ImportOrigin.note => PortfolioLoadMethod.note,
  };
}

enum ImportPhase { intro, reading, preview, importing, done }

class StatementImportState {
  const StatementImportState({
    this.phase = ImportPhase.intro,
    this.rows = const [],
    this.source = ImportSource.csv,
    this.warnings = const [],
    this.errorType,
    this.currentPrices = const {},
    this.held = const {},
    this.sellMissing = const {},
    this.positionLimit,
    this.importedCount = 0,
    this.failedTickers = const [],
    this.origin = ImportOrigin.file,
  });

  final ImportPhase phase;
  final List<ImportRow> rows;
  final ImportSource source;
  final List<ImportWarning> warnings;

  /// El último error (`StatementImportException.type`), para mostrarlo en
  /// la pantalla de inicio. `null` si no hubo.
  final String? errorType;

  /// Precio de hoy de cada ticker con cotización (del chequeo de tickers).
  final Map<String, double> currentPrices;

  /// Lo que el usuario ya tiene en la cartera, por ticker.
  final Map<String, HeldHolding> held;

  /// Tickers que tiene y no están en el archivo, marcados para registrarlos
  /// como vendidos.
  final Set<String> sellMissing;

  /// Tickers que el usuario ya tiene en la cartera.
  Set<String> get heldTickers => held.keys.toSet();

  /// Tope de posiciones (distintos tickers) del plan; `null` = sin tope.
  final int? positionLimit;

  final int importedCount;
  final List<String> failedTickers;
  final ImportOrigin origin;

  List<ImportRow> get included => [
    for (final r in rows)
      if (r.included) r,
  ];

  /// Qué hace la importación con [row], comparada con la cartera.
  ImportPlan planFor(ImportRow row) =>
      HoldingDiff.plan(row, held[row.ticker], currentPrices[row.ticker]);

  /// Lista para aplicar: una nueva con todos sus datos, o una diferencia
  /// con ticker conocido y precio.
  bool isRowReady(ImportRow row) {
    final plan = planFor(row);
    return switch (plan.action) {
      ImportAction.add => row.isReady,
      ImportAction.unchanged => false,
      ImportAction.buyMore || ImportAction.sell =>
        row.quote == QuoteCheck.found && row.quantity > 0 && plan.price != null,
    };
  }

  /// Las que se pueden importar ya.
  List<ImportRow> get ready => [
    for (final r in included)
      if (isRowReady(r)) r,
  ];

  /// Las incluidas a las que les falta algo (las iguales no cuentan).
  int get needsAttention =>
      included
          .where(
            (r) =>
                planFor(r).action != ImportAction.unchanged && !isRowReady(r),
          )
          .length;

  /// Las del archivo que ya coinciden con la cartera.
  int get unchangedCount =>
      rows.where((r) => planFor(r).action == ImportAction.unchanged).length;

  /// Las que cambian una posición que ya tiene (comprar o vender la
  /// diferencia).
  int get changedCount =>
      rows.where((r) {
        final a = planFor(r).action;
        return a == ImportAction.buyMore || a == ImportAction.sell;
      }).length;

  /// Tickers que tiene (en manuales y con precio de hoy) y no aparecen en
  /// el archivo. Solo con un archivo: una captura o lo que escribe pueden
  /// ser solo una parte.
  List<String> get missing {
    if (origin != ImportOrigin.file) return const [];
    final inFile = {for (final r in rows) r.ticker};
    return [
      for (final e in held.entries)
        if (e.value.quantity > 1e-9 &&
            e.value.currentPrice != null &&
            !inFile.contains(e.key))
          e.key,
    ]..sort();
  }

  /// Solo agrega posiciones nuevas (los textos de antes alcanzan).
  bool get onlyAdds =>
      sellMissing.isEmpty &&
      ready.every((r) => planFor(r).action == ImportAction.add);

  /// Movimientos que se van a aplicar.
  int get changesToApply => ready.length + sellMissing.length;

  bool get checkingQuotes =>
      rows.any((r) => r.included && r.quote == QuoteCheck.pending);

  /// Tickers nuevos (que no tiene) entre las que se van a importar.
  Set<String> get newTickers => {
    for (final r in ready)
      if (!heldTickers.contains(r.ticker)) r.ticker,
  };

  /// Importarlas pasaría el tope de posiciones del plan.
  bool get exceedsLimit =>
      positionLimit != null &&
      heldTickers.length + newTickers.length > positionLimit!;

  bool get canImport =>
      phase == ImportPhase.preview &&
      changesToApply > 0 &&
      !checkingQuotes &&
      !exceedsLimit;

  int get missingDates => included.where((r) => r.purchaseDate == null).length;

  /// Sin precio de compra pero con precio de hoy conocido.
  int get missingPricesFillable =>
      included
          .where(
            (r) =>
                r.purchasePrice == null && currentPrices.containsKey(r.ticker),
          )
          .length;

  StatementImportState copyWith({
    ImportPhase? phase,
    List<ImportRow>? rows,
    ImportSource? source,
    List<ImportWarning>? warnings,
    String? errorType,
    bool clearError = false,
    Map<String, double>? currentPrices,
    Map<String, HeldHolding>? held,
    Set<String>? sellMissing,
    int? positionLimit,
    int? importedCount,
    List<String>? failedTickers,
    ImportOrigin? origin,
  }) {
    return StatementImportState(
      phase: phase ?? this.phase,
      rows: rows ?? this.rows,
      source: source ?? this.source,
      warnings: warnings ?? this.warnings,
      errorType: clearError ? null : (errorType ?? this.errorType),
      currentPrices: currentPrices ?? this.currentPrices,
      held: held ?? this.held,
      sellMissing: sellMissing ?? this.sellMissing,
      positionLimit: positionLimit ?? this.positionLimit,
      importedCount: importedCount ?? this.importedCount,
      failedTickers: failedTickers ?? this.failedTickers,
      origin: origin ?? this.origin,
    );
  }
}

/// Importar posiciones desde un CSV o PDF: elegir el archivo, leerlo en el
/// servidor, compararlo con la cartera, corregir la vista previa y aplicar
/// las diferencias como movimientos manuales (compras nuevas, la
/// diferencia comprada o vendida, y lo que ya no está).
class StatementImportNotifier extends StateNotifier<StatementImportState> {
  StatementImportNotifier({
    required StatementImportClient client,
    required StatementPicker pick,
    StatementPicker? pickScreenshot,
    required GetCurrentPriceUseCase getCurrentPrice,
    required AddPositionUseCase addPosition,
    required ClosePositionUseCase closePosition,
    required Map<String, HeldHolding> Function() held,
    required int? Function() positionLimit,
    Future<void> Function(ImportOrigin origin)? onImported,
    DateTime Function()? now,
  }) : _client = client,
       _pick = pick,
       _pickScreenshot = pickScreenshot,
       _getCurrentPrice = getCurrentPrice,
       _addPosition = addPosition,
       _closePosition = closePosition,
       _held = held,
       _positionLimit = positionLimit,
       _onImported = onImported,
       _now = now ?? DateTime.now,
       super(const StatementImportState());

  final StatementImportClient _client;
  final StatementPicker _pick;
  final StatementPicker? _pickScreenshot;
  final GetCurrentPriceUseCase _getCurrentPrice;
  final AddPositionUseCase _addPosition;
  final ClosePositionUseCase _closePosition;
  final Map<String, HeldHolding> Function() _held;
  final int? Function() _positionLimit;
  final Future<void> Function(ImportOrigin origin)? _onImported;
  final DateTime Function() _now;

  /// Elige un archivo y lo lee. Si el usuario cancela, no cambia nada.
  Future<void> pickAndRead() => _pickAndRead(_pick, ImportOrigin.file);

  /// Elige una captura de la galería y la lee (con IA).
  Future<void> pickScreenshotAndRead() =>
      _pickAndRead(_pickScreenshot ?? _pick, ImportOrigin.screenshot);

  Future<void> _pickAndRead(StatementPicker pick, ImportOrigin origin) async {
    if (state.phase == ImportPhase.reading) return;
    final PickedStatement? file;
    try {
      file = await pick();
    } catch (_) {
      if (mounted) state = state.copyWith(errorType: 'picker_failed');
      return;
    }
    if (file == null || !mounted) return;
    await read(file, origin: origin);
  }

  Future<void> read(
    PickedStatement file, {
    ImportOrigin origin = ImportOrigin.file,
  }) =>
      _read(() => _client.read(filename: file.name, bytes: file.bytes), origin);

  /// Lo que escribió el usuario ("10 VOO, 2000 dólares en QQQ…"): lo lee la
  /// IA y sale la misma vista previa para revisar.
  Future<void> readNote(String text) {
    if (state.phase == ImportPhase.reading || text.trim().isEmpty) {
      return Future.value();
    }
    return _read(() => _client.readNote(text.trim()), ImportOrigin.note);
  }

  Future<void> _read(
    Future<StatementReadResult> Function() fetch,
    ImportOrigin origin,
  ) async {
    state = state.copyWith(
      phase: ImportPhase.reading,
      clearError: true,
      origin: origin,
    );
    try {
      final result = await fetch();
      if (!mounted) return;
      final held = _held();
      state = StatementImportState(
        phase: ImportPhase.preview,
        // Lo que ya llega de un bróker conectado arranca afuera: el archivo
        // suele ser de ese mismo bróker y se duplicaría.
        rows: [
          for (final r in result.rows)
            held[r.ticker]?.broker != null ? r.copyWith(included: false) : r,
        ],
        source: result.source,
        warnings: result.warnings,
        held: held,
        positionLimit: _positionLimit(),
        origin: origin,
      );
      unawaited(_checkQuotesAndFill(origin));
    } on StatementImportException catch (e) {
      if (!mounted) return;
      state = state.copyWith(phase: ImportPhase.intro, errorType: e.type);
    }
  }

  /// Lo que escribe o una captura casi nunca traen fecha ni precio de
  /// compra: se completan con los de hoy (la vista previa lo dice y se
  /// corrigen tocando la fila). Un archivo, no: ahí faltar es raro y se
  /// pregunta.
  Future<void> _checkQuotesAndFill(ImportOrigin origin) async {
    await checkQuotes();
    if (!mounted || origin == ImportOrigin.file) return;
    if (state.phase != ImportPhase.preview) return;
    fillMissingDatesWithToday();
    fillMissingPricesWithCurrent();
  }

  /// Busca la cotización de cada ticker pendiente (de a pocos a la vez).
  Future<void> checkQuotes() async {
    final pending =
        {
          for (final r in state.rows)
            if (r.quote == QuoteCheck.pending) r.ticker,
        }.toList();
    const batch = 6;
    for (var i = 0; i < pending.length; i += batch) {
      final slice = pending.skip(i).take(batch).toList();
      final prices = await Future.wait(slice.map(_priceOf));
      if (!mounted) return;
      final found = <String, double>{};
      final missing = <String>{};
      for (var j = 0; j < slice.length; j++) {
        final p = prices[j];
        if (p != null) {
          found[slice[j]] = p;
        } else {
          missing.add(slice[j]);
        }
      }
      state = state.copyWith(
        currentPrices: {...state.currentPrices, ...found},
        rows: [
          for (final r in state.rows)
            if (r.quote != QuoteCheck.pending)
              r
            else if (found.containsKey(r.ticker))
              _withQuote(r, found[r.ticker]!)
            else if (missing.contains(r.ticker))
              r.copyWith(quote: QuoteCheck.notFound)
            else
              r,
        ],
      );
    }
  }

  /// Con cotización. Si dijo cuánta plata tiene y no cuántas unidades, la
  /// cantidad sale de dividir por el precio de hoy.
  static ImportRow _withQuote(ImportRow r, double price) {
    final amount = r.amount;
    if (r.quantity > 0 || amount == null || price <= 0) {
      return r.copyWith(quote: QuoteCheck.found);
    }
    return r.copyWith(
      quote: QuoteCheck.found,
      quantity: (amount / price * 1e6).roundToDouble() / 1e6,
      quantityFromAmount: true,
    );
  }

  Future<double?> _priceOf(String ticker) async {
    try {
      final result = await _getCurrentPrice(
        params: PortfolioCalculator.toYahooFinanceSymbol(ticker),
      );
      return result.fold<double?>((_) => null, (p) => p > 0 ? p : null);
    } catch (_) {
      return null;
    }
  }

  void toggle(int id) {
    _replace(id, (r) => r.copyWith(included: !r.included));
  }

  void updateRow(
    int id, {
    String? ticker,
    double? quantity,
    double? purchasePrice,
    DateTime? purchaseDate,
  }) {
    _replace(
      id,
      (r) => r.copyWith(
        ticker:
            ticker == null ? null : PortfolioCalculator.normalizeTicker(ticker),
        quantity: quantity,
        purchasePrice: purchasePrice,
        purchaseDate: purchaseDate,
      ),
    );
    if (state.rows.any((r) => r.quote == QuoteCheck.pending)) {
      unawaited(checkQuotes());
    }
  }

  /// Las que no tienen fecha pasan a tener la de hoy.
  void fillMissingDatesWithToday() {
    final today = _now();
    final date = DateTime(today.year, today.month, today.day);
    state = state.copyWith(
      rows: [
        for (final r in state.rows)
          r.purchaseDate == null ? r.copyWith(purchaseDate: date) : r,
      ],
    );
  }

  /// Las que no tienen precio de compra pasan a tener el de hoy (la
  /// ganancia arranca en cero).
  void fillMissingPricesWithCurrent() {
    state = state.copyWith(
      rows: [
        for (final r in state.rows)
          r.purchasePrice == null && state.currentPrices[r.ticker] != null
              ? r.copyWith(purchasePrice: state.currentPrices[r.ticker])
              : r,
      ],
    );
  }

  /// Marca o desmarca un ticker que no está en el archivo para
  /// registrarlo como vendido.
  void toggleMissing(String ticker) {
    final next = {...state.sellMissing};
    if (!next.remove(ticker)) next.add(ticker);
    state = state.copyWith(sellMissing: next);
  }

  /// Aplica lo listo como movimientos manuales, uno por uno: las nuevas se
  /// agregan, las diferencias se compran o venden (FIFO, como el resto de
  /// la app) con fecha de hoy, y lo marcado que ya no está se vende entero
  /// al precio de hoy. Lo que falla queda en
  /// [StatementImportState.failedTickers].
  Future<void> importReady() async {
    if (!state.canImport) return;
    final snapshot = state;
    state = state.copyWith(phase: ImportPhase.importing);
    final now = _now();
    final today = DateTime(now.year, now.month, now.day);
    var imported = 0;
    final failed = <String>[];
    for (final r in snapshot.ready) {
      final plan = snapshot.planFor(r);
      final Either<HttpError, Object> result = switch (plan.action) {
        ImportAction.add || ImportAction.unchanged => await _addPosition(
          params: AddPositionParams(
            ticker: r.ticker,
            quantity: r.quantity,
            purchasePrice: r.purchasePrice!,
            purchaseDate: r.purchaseDate!,
          ),
        ),
        ImportAction.buyMore => await _addPosition(
          params: AddPositionParams(
            ticker: r.ticker,
            quantity: plan.quantity,
            purchasePrice: plan.price!,
            purchaseDate: today,
          ),
        ),
        ImportAction.sell => await _sell(
          r.ticker,
          plan.quantity,
          plan.price!,
          today,
        ),
      };
      result.fold((_) => failed.add(r.ticker), (_) => imported++);
    }
    for (final ticker in snapshot.sellMissing) {
      final h = snapshot.held[ticker];
      if (h == null || h.currentPrice == null) continue;
      final result = await _sell(ticker, h.quantity, h.currentPrice!, today);
      result.fold((_) => failed.add(ticker), (_) => imported++);
    }
    if (imported > 0) await _onImported?.call(state.origin);
    if (!mounted) return;
    state = state.copyWith(
      phase: ImportPhase.done,
      importedCount: imported,
      failedTickers: failed,
    );
  }

  /// Vuelve al inicio (elegir otro archivo).
  void reset() {
    state = const StatementImportState();
  }

  /// Con el ticker (no un lote) el repositorio vende FIFO entre las
  /// compras manuales.
  Future<Either<HttpError, Object>> _sell(
    String ticker,
    double quantity,
    double price,
    DateTime date,
  ) => _closePosition(
    params: ClosePositionParams(
      positionId: ticker,
      quantity: quantity,
      closePrice: price,
      closeDate: date,
    ),
  );

  void _replace(int id, ImportRow Function(ImportRow) change) {
    state = state.copyWith(
      rows: [for (final r in state.rows) r.id == id ? change(r) : r],
    );
  }
}

final statementImportProvider = StateNotifierProvider.autoDispose<
  StatementImportNotifier,
  StatementImportState
>(
  (ref) => StatementImportNotifier(
    client: ref.watch(statementImportClientProvider),
    pick: ref.watch(statementPickerProvider),
    pickScreenshot: ref.watch(screenshotPickerProvider),
    getCurrentPrice: ref.watch(getCurrentPriceUseCaseProvider),
    addPosition: ref.watch(addPositionUseCaseProvider),
    closePosition: ref.watch(closePositionUseCaseProvider),
    held:
        () => HeldHolding.fromLots(
          ref.read(homeProvider).summary?.lots ?? const [],
        ),
    positionLimit:
        () => SubscriptionPolicy.positionLimit(
          ref.read(subscriptionProvider).tier,
        ),
    onImported: (origin) {
      // Si era la primera carga, la Home la registra con el camino (archivo,
      // captura o escrita).
      ref.read(portfolioLoadMethodProvider.notifier).state = origin.loadMethod;
      return ref.read(homeProvider.notifier).refresh(silent: true);
    },
  ),
);
