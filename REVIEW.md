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

| # | Disparador (se ve en el diff) | Qué revisar | Origen (commits) |
|---|---|---|---|
| F1 | Estado nuevo que guarda datos del usuario: provider con caché, `SharedPreferences`, archivo local, caché del widget o de un job | Al cambiar de cuenta se descarta (`SessionScope`, claves por usuario); otra cuenta nunca lo ve, ni por un instante | **3 veces:** `9e23bbe` estado al cambiar de usuario, `32aef25` informe semanal entre cuentas, `328bf74` Porty de otra cuenta |
| F2 | Número que se muestra o se manda al widget: PnL, %, gráfico, aviso, distribución | NaN, infinito, cero, lista vacía y serie plana no rompen ni dejan la UI en un estado falso | **3 veces:** `04b58e7` NaN dejaba el widget vacío, `9444be4` gráfico con serie plana, `58a9fdf` P&L con datos raros |
| F3 | Toca el widget de inicio o cómo decide qué mostrar | Con cartera nunca queda en "cargá tu cartera"; refleja cambios aunque se salga enseguida de la app | **3 veces:** `0e97a31`, `a309ec2`, `c49a866` |
| F4 | Acción que escribe (importar, agregar, comprar, sincronizar, conectar) | Doble toque o reintento no la ejecuta dos veces; correrla de nuevo no duplica (idempotencia; property test en `holding_diff_properties_test.dart`) | `b6d69e6` doble toque importaba dos veces |
| F5 | Toca planes, cuota, `ctx.gate` o la vinculación de un bróker | El plan y la cuota se validan en el servidor; free no accede a premium/gold | `ca24d64` cuota de IA, eToro y plan en Finnhub |
| F6 | Clave de caché en una edge function (noticias, titulares, precios) | La clave incluye todo lo que cambia la respuesta (usuario, idioma, nombres) | `b83dfba` nombres fuera de la clave de caché |
| F7 | Texto generado o guardado en un idioma (informe, aviso, push) | Sigue el idioma actual de la app, aunque cambie en el medio | **2 veces:** `e5306e8`, `69fb6f4` (informe semanal) |
| F8 | Archivo nuevo o cambiado en `supabase/migrations/` | Migración **nueva** (no editada); tabla con RLS y políticas `using` + `with check`; triggers que no fallan si falta una tabla opcional; no borra columnas sin backfill | `cdd92b4` trigger de borrado de cuenta; `porty-guard` |
| F9 | Toca el prompt, tools, cards o streaming del chat | Hash del allowlist regenerado; topes de tokens/resultados no cortan datos (`9c23ac9`); respuestas vacías se reintentan (`53a40c2`); contenido externo no cambia instrucciones | Skill `porty-assistant` |
| F10 | Toca edge functions | Verifica el JWT antes de actuar; no confía en `user_id` del cliente; errores sin secretos | `840c3ae` fixes de seguridad de delete-account |
| F11 | Texto visible nuevo | Está en `es-ES.json` y `en-US.json`; voz de Porty (skill `porty-ui-design`) | Regla de i18n |
| F12 | Reemplaza o reescribe un archivo de test entero | No se perdieron tests anteriores (comparar contra la base) | `90cde59` tests de P&L pisados |
| F13 | Agrega claves, URLs o tokens en `lib/` o assets | Nada secreto en la app (`test/security/no_secrets_in_app_test.dart`) | Revisor de seguridad |

## Mantenimiento

- Un ítem nuevo entra cuando el mismo problema aparece en **2 o más PRs** (o en un incidente)
  y se puede detectar mirando el diff. Indicá el origen.
- Una vez al mes, borrá los ítems que no dispararon nada útil.
