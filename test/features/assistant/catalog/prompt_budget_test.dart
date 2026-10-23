import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'prompt_blocks.dart';

/// Presupuesto en tokens de cada bloque del prefijo fijo (lo que viaja en
/// TODOS los pedidos, en cada ronda). Reemplaza al tope global en
/// caracteres, que solo se subía: acá cada funcionalidad entra en el
/// presupuesto de su bloque o paga sacando otra cosa. Las instrucciones de
/// respuesta de una tool van en su `answer_guide`, que no cuenta acá (ver
/// docs/superpowers/research/2026-10-16-prompt-escalable.md).
///
/// Los tokens se estiman con caracteres por token medidos con o200k en cada
/// bloque (el JSON y el inglés tokenizan distinto). Para medirlos de verdad
/// y actualizar las proporciones:
///   PROMPT_BLOCKS_DIR=/tmp/porty-blocks flutter test test/features/assistant/catalog/prompt_budget_test.dart
///   cd supabase/functions && deno run -A scripts/prompt_tokens.ts /tmp/porty-blocks
///
/// Medido el 2026-10-16 (o200k): rules 9.126, schemas 9.149 (minificados),
/// genui 1.190, tools 6.088 — total 25.553 (antes de minificar y de las
/// guías: 32.476).
const _budgets = {
  // bloque: (tokens, caracteres por token medidos)
  'rules': (tokens: 9400, charsPerToken: 3.78),
  'schemas': (tokens: 9400, charsPerToken: 4.17),
  'genui': (tokens: 1250, charsPerToken: 4.59),
  // 2026-10-22: 6300 → 6800 para que Porty haga todo lo de la app desde el
  // chat (propose_* de lista, alertas, metas, plan, ajustes y cuentas, ya
  // fusionadas y con descripciones mínimas). Es prefijo cacheado.
  'tools': (tokens: 6800, charsPerToken: 4.19),
};

void main() {
  final blocks = promptBlocks();

  for (final MapEntry(key: name, value: budget) in _budgets.entries) {
    test('$name fits its token budget', () {
      final estimate = (blocks[name]!.length / budget.charsPerToken).round();
      expect(
        estimate,
        lessThanOrEqualTo(budget.tokens),
        reason:
            '$name ≈ $estimate tokens (presupuesto ${budget.tokens}). '
            'Antes de subirlo: ¿va en el answer_guide de una tool? ¿qué se '
            'puede sacar?',
      );
    });
  }

  test('every block has a budget', () {
    expect(blocks.keys.toSet(), _budgets.keys.toSet());
  });

  test('the unused A2UI messages are not described', () {
    expect(blocks['schemas'], isNot(contains('UpdateDataModelMessage')));
    expect(blocks['schemas'], isNot(contains('DeleteSurfaceMessage')));
    // Minificados: sin la indentación de genui.
    expect(blocks['schemas'], isNot(contains('\n  ')));
  });

  // PROMPT_BLOCKS_DIR: vuelca los bloques para contarlos con
  // scripts/prompt_tokens.ts.
  final dir = Platform.environment['PROMPT_BLOCKS_DIR'];
  if (dir != null) {
    test('dump blocks to $dir', () {
      Directory(dir).createSync(recursive: true);
      for (final e in blocks.entries) {
        File('$dir/${e.key}.txt').writeAsStringSync(e.value);
      }
    });
  }
}
