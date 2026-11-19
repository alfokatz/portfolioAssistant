import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

/// Property tests escritos a mano (sin dependencias, como los fakes): se
/// generan muchas entradas al azar con una semilla fija y se comprueba una
/// regla que tiene que valer SIEMPRE.
///
/// Si falla, el mensaje trae la semilla y la entrada que la rompió. Para
/// reproducir: `PROPERTY_SEED=<semilla> flutter test <archivo>`.
/// Para buscar más casos: `PROPERTY_RUNS=20000 flutter test <archivo>`.
void property<T>(
  String description, {
  required T Function(Random rnd) generate,
  required void Function(T input) check,
  int runs = 500,
}) {
  test('propiedad: $description', () {
    const seedEnv = String.fromEnvironment('PROPERTY_SEED');
    const runsEnv = String.fromEnvironment('PROPERTY_RUNS');
    final seed = int.tryParse(seedEnv) ?? 20261117;
    final total = int.tryParse(runsEnv) ?? runs;
    final rnd = Random(seed);
    for (var i = 0; i < total; i++) {
      final input = generate(rnd);
      try {
        check(input);
      } catch (e) {
        fail(
          'Se rompió en la corrida $i (semilla $seed).\n'
          'Entrada: $input\n'
          'Error: $e',
        );
      }
    }
  });
}

/// Generadores chicos y sesgados hacia los bordes (0, valores minúsculos,
/// enormes, repetidos), que es donde se rompen las cuentas.
abstract final class Gen {
  static const _tickers = [
    'AAPL',
    'MSFT',
    'VOO',
    'QQQ',
    'NVDA',
    'BTC',
    'ETH',
    'GGAL',
    'YPF',
    'SPY',
  ];

  static String ticker(Random r) => _tickers[r.nextInt(_tickers.length)];

  /// Lista de tickers distintos, de 0 a [max].
  static List<String> tickers(Random r, {int min = 0, int max = 8}) {
    final n = min + r.nextInt(max - min + 1);
    return (List.of(_tickers)..shuffle(r)).take(n).toList();
  }

  /// Un monto no negativo con bordes: 0, centavos, normales y enormes.
  static double amount(Random r) => switch (r.nextInt(10)) {
    0 => 0,
    1 => (r.nextInt(100) + 1) / 100,
    2 => 1e7 * r.nextDouble(),
    3 => 1e-6 * (r.nextInt(9) + 1),
    _ => (r.nextDouble() * 50000 * 100).roundToDouble() / 100,
  };

  /// Una cantidad de unidades (acciones o fracciones de cripto).
  static double quantity(Random r) => switch (r.nextInt(8)) {
    0 => 0.00000001 * (r.nextInt(999) + 1),
    1 => (r.nextInt(5000) + 1).toDouble(),
    2 => 1,
    _ => (r.nextDouble() * 500 * 1e4).roundToDouble() / 1e4,
  };
}
