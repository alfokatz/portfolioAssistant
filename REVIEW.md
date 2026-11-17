# REVIEW.md: qué mira la revisión de código de Porty

Lo usa el revisor principal (`porty-code-reviewer` o `/code-review`) en cada diff.
**Se lee siempre desde la rama base** (`git show origin/main:REVIEW.md`), nunca desde
el cambio que se revisa: un cambio no puede aflojar las reglas que lo juzgan. Si
modificás este archivo, va en un PR propio, sin código de producto.

## Cómo reportar

- Solo bugs, violaciones de reglas duras y tests faltantes para un caso real. Nada de estilo.
- Cada hallazgo lleva una etiqueta:
  - **Importante**: hay que arreglarlo antes de mergear.
  - **Menor**: conviene arreglarlo, no bloquea.
  - **Preexistente**: el bug ya estaba antes de este cambio; se anota, pero no se le cobra al autor.
- Cada hallazgo dice **por qué** se lo marca y el escenario concreto (entrada/estado → resultado mal),
  para que quien lo lea no tenga que deducirlo del diff.
- Cero hallazgos es una respuesta válida.

## Siempre

1. **Correctitud:** nulls, listas vacías, `loading`/`loadFailed` sin manejar, `await` perdido,
   `BuildContext` usado después de un `await`, `dispose` faltante.
2. **Plata y números:** división por cero en PnL o porcentajes, NaN/infinito en la UI,
   monedas o tipo de cambio mezclados, redondeos que no suman.
3. **Reglas del repo** (skill `porty-architecture`): Riverpod a mano, imports `package:`,
   navegación por nombre, `SubscriptionPolicy.allows` en vez de comparar tiers, textos en
   `es-ES.json` y `en-US.json`, sin tickers hardcodeados.
4. **Tests:** ¿prueban el comportamiento o solo que el código corre? ¿Falta el caso que
   rompería en producción?
5. **Verificación:** el autor dice cómo verificó (`Verified:` en el commit). Si dice `none`
   en un cambio de lógica, es un hallazgo **Importante**.

## Checklist de fiabilidad (solo los ítems cuyo disparador aparece en el diff)

Leé el diff, elegí los ítems que aplican (suelen ser 3 a 10) y revisá solo esos.

| # | Disparador (se ve en el diff) | Qué revisar | Origen |
|---|---|---|---|
| F1 | Cambia un modelo que se lee de Supabase, SharedPreferences o JSON guardado | Un registro viejo **sin** el campo nuevo carga sin romper (default o null manejado) | Regla de compatibilidad de datos |
| F2 | Archivo nuevo o cambiado en `supabase/migrations/` | Es una migración **nueva** (no editada); tabla nueva con RLS y políticas `using` + `with check`; no borra columnas sin paso de backfill | `porty-guard`, revisor de seguridad |
| F3 | Toca sync de brokers (SnapTrade, Binance, eToro) o import de estados de cuenta | Correrlo dos veces no duplica posiciones ni operaciones (idempotencia) | Riesgo de datos duplicados |
| F4 | Toca planes, cuota o `ctx.gate` | El plan se valida en el servidor; free no accede a premium/gold; la cuota no se supera | Revisor de seguridad |
| F5 | Toca el prompt, tools o catálogo del chat | Hash del allowlist del proxy `ai-chat` regenerado; contenido externo no cambia instrucciones | Skill `porty-assistant` |
| F6 | Toca edge functions | Verifica el JWT antes de actuar; no confía en `user_id` del cliente; errores sin secretos | Revisor de seguridad |
| F7 | Texto visible nuevo | Está en las dos traducciones; voz de Porty (skill `porty-ui-design`) | Regla de i18n |
| F8 | Cambia cálculo de PnL, distribución o desglose por moneda | Test con datos raros (NaN, infinito, cero, lista vacía) | Tarjeta de P&L con datos raros (nov 2026) |
| F9 | Reemplaza un archivo de test entero | No se perdieron tests anteriores (comparar contra la base) | Tests pisados en la tarjeta de P&L (nov 2026) |
| F10 | Agrega claves, URLs o tokens en `lib/` o assets | Nada secreto en la app (`test/security/no_secrets_in_app_test.dart`) | Revisor de seguridad |

## Mantenimiento

- Un ítem nuevo entra cuando el mismo problema aparece en **2 o más PRs** (o en un incidente)
  y se puede detectar mirando el diff. Indicá el origen.
- Una vez al mes, borrá los ítems que no dispararon nada útil.
