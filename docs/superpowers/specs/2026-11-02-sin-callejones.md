# Spec: momentos de intención sin callejones

**Fecha:** 2026-11-02 · **Autor:** porty-architect · **Estado:** lista para construir
**Implementa:** apuesta #3 de `docs/product/roadmap.md` (3a, 3b, 3c). Decisiones del 2026-11-02 en `docs/product/decisions.md` (salida gratis en Binance/SnapTrade; puente al pago al final del diagnóstico sin modal; aviso de cuota y fecha de renovación). Insumo: `docs/growth/2026-11-02-palancas-a-pago.md` E1 y E2; auditoría de monetización P5.
**Depende de:** `docs/superpowers/specs/2026-11-02-paywall-medible-y-anual.md` (eventos de paywall, `PaywallSource`, `source` obligatorio, `ConversionFlags`). Esta spec no redefine nada de esa.

---

## 1. Objetivo

Tres lugares donde el usuario ya mostró intención terminan hoy en una pared o en nada:

- **3a.** Free que elige Binance u "Otro bróker" ve solo "Ver planes". Se suma una salida gratis: "Mientras tanto, traela con una captura", que lleva a importar resumen.
- **3b.** El diagnóstico termina en "Ir a mi cartera". Se suman dos filas tranquilas antes del final: "que se actualice sola" (puente al pago, `source: diagnosis_sync`) y "¿te aviso el sábado?" (permiso de push, `push_opt_in{source: diagnosis}`).
- **3c.** Free se entera de la cuota recién en 0. Se suma una línea en el chat cuando quedan 5 de 20 (una vez por mes), y el paywall de cuota dice cuándo vuelven las consultas.

Cada cambio tiene su `source` y su interruptor en `app_config`. **Listo** = criterios de §5 en verde y los tres interruptores probados prendidos y apagados.

## 2. Fuera de alcance

- Binance gratis la primera vez (diciembre, lo decide monetización + usuario).
- Cambiar el límite de 20, los precios, o cualquier cosa que Free ya tenga. El diagnóstico sigue completo en Free.
- Modales, contadores de urgencia o paywalls automáticos.
- Prueba de Gold en el paywall de cuota.
- Impresiones de las filas nuevas (`*_shown`): los denominadores salen de `diagnosis_seen`, `onboarding_finished{exit}` y `ai_usage_monthly` (ver §3.5).
- Cambios en el prompt, las tools o el catálogo del chat. **No toca la allowlist** (ver §6).

---

## 3. Contrato de datos

### 3.1 Interruptores en `app_config` (migración nueva)

`supabase/migrations/20261102120200_conversion_nudge_flags.sql` (dueño backend-dev). Formato `PortyRolloutFlag`, **arrancan apagados**:

```sql
insert into public.app_config (key, value) values
  ('broker_screenshot_exit', '{"percent": 0, "users": []}'::jsonb),  -- 3a
  ('diagnosis_bridge',       '{"percent": 0, "users": []}'::jsonb),  -- 3b (las dos filas)
  ('quota_nudge',            '{"percent": 0, "users": []}'::jsonb)   -- 3c (línea en el chat)
on conflict (key) do nothing;
```

Para prender (lo hace el usuario):

```sql
update public.app_config set value = '{"percent": 100, "users": []}'::jsonb, updated_at = now()
 where key in ('broker_screenshot_exit', 'diagnosis_bridge', 'quota_nudge');
```

En la app, se suman a `lib/features/subscription/config/conversion_flags.dart` (archivo de la spec anterior, dueño flutter-dev):

```dart
static final brokerScreenshotExit = PortyRolloutFlag('broker_screenshot_exit');
static final diagnosisBridge = PortyRolloutFlag('diagnosis_bridge');
static final quotaNudge = PortyRolloutFlag('quota_nudge');

final brokerScreenshotExitEnabledProvider = FutureProvider<bool>(...);
final diagnosisBridgeEnabledProvider = FutureProvider<bool>(...);
final quotaNudgeEnabledProvider = FutureProvider<bool>(...);   // lo lee assistant-dev
```

Falla cerrado: sin red o sin fila, todo se ve como hoy. La fecha de renovación en el paywall de cuota (§3.4) **no** lleva interruptor: es información, no una venta.

### 3.2 Orígenes y motivos nuevos

En `PaywallSource` (flutter-dev):

| Constante | Valor | Lugar | `PaywallReason` |
|---|---|---|---|
| `diagnosisSync` | `diagnosis_sync` | fila "que se actualice sola" del diagnóstico (solo si el plan no incluye `brokerSync`) | `brokerSync` |
| `quotaSoft` | `quota_soft` | línea de cuota del chat | `quotaLow` (nuevo) |

`binance_connect`, `snaptrade_connect` y `quota_zero` ya existen (spec anterior) y no cambian.

`PaywallReason.quotaLow` (nuevo, en `subscription_provider.dart`): tiers visibles como `quotaExceeded`; **con** medidor de uso.

### 3.3 Planes: cuándo avisar

En `lib/domain/subscription/plan_matrix.dart` (flutter-dev), por capacidad y no por tier:

```dart
// PlanSpec
/// Avisar en el chat cuando quedan estas consultas del mes. null = no avisar.
final int? quotaNudgeAtRemaining;   // Free: 5. Premium y Gold: null.

// PlanMatrix
/// El plan siguiente (para "Con Premium tenés 500"). null en Gold.
static SubscriptionTier? nextTier(SubscriptionTier tier);
```

### 3.4 Lo que ve el usuario

**3a. Pantallas bloqueadas de Binance y SnapTrade** (`binance_screen.dart`, `snaptrade_screen.dart`), solo en el estado `!allowed` y con `brokerScreenshotExitEnabledProvider == true`. Debajo de la nota "Conectar … es de Premium": un `TextButton.icon` secundario (≥ 48 dp, ícono `Icons.photo_camera_outlined`). "Ver planes" sigue primero y no cambia.
- Toque: `nudge_tapped{surface, action: 'screenshot'}` y `context.pushNamed(StatementImportRouter.routeName)` (la pantalla ya ofrece captura, archivo y escribirlo; no hace falta parámetro nuevo).

**3b. Final del diagnóstico** (`portfolio_diagnosis_screen.dart`), con `diagnosisBridgeEnabledProvider == true`, dentro de `_DiagnosisBody`, después de las preguntas y antes de `diagnosis_note`. Reusa `_FindingRow.action`. Sin modal, sin color de alerta.
- **Fila sync**: visible si ninguna posición de la Home tiene `source.hasImported` (cargó por archivo, captura, texto o a mano).
  - Plan sin `PlanFeature.brokerSync` → `SubscriptionPaywallSheet.show(reason: brokerSync, source: PaywallSource.diagnosisSync)`.
  - Plan con `brokerSync` → `context.pushNamed(ConnectBrokerRouter.routeName)` (sin paywall), con el detalle sin "Premium".
- **Fila push**: visible si `pushControllerProvider.permission == PushPermission.notDetermined` (sin Firebase queda `unavailable` y no se ve). Toque → `PushPermissionSheet.maybeShow(context, ref, reason: PushPromptReason.diagnosis, force: true)` (`force` porque el usuario lo pidió con un toque). Después del resultado la fila desaparece.

**3c. Cuota.**
- **Línea en el chat** (assistant-dev). Después de un turno que cobró, con la cuota ya refrescada: si `quotaNudgeEnabledProvider == true`, `PlanMatrix.of(tier).quotaNudgeAtRemaining != null`, `0 < queriesRemaining <= quotaNudgeAtRemaining`, `PlanMatrix.nextTier(tier) != null` y no se mostró este mes (mes UTC, igual que `_current_usage_month`, por usuario, en SharedPreferences: clave `quota_nudge_shown`, lista de `"<userId>:YYYY-MM"`), la respuesta de ese turno lleva debajo una línea en texto secundario, estilo `AssistantQuietNotice` (no es un error ni una card), con un link "Ver planes" → `SubscriptionPaywallSheet.show(reason: PaywallReason.quotaLow, source: PaywallSource.quotaSoft)`. No es un widget del catálogo ni lo escribe el modelo.
  - Modelo: `PortfolioQaMessage` suma `final int? quotaNudgeRemaining;` (con `copyWith`). El número sale de `subscriptionProvider`, nunca del modelo.
- **Paywall de cuota** (flutter-dev). Con `quotaExceeded` y `quotaLow`, debajo del subtítulo: `Tus consultas vuelven el {date}.`, donde `date` = día 1 del mes UTC siguiente, con `DateFormat.MMMMd(locale)` ("1 de diciembre" / "December 1").

**Claves de traducción** (flutter-dev las agrega todas, también las del chat; `es-ES.json` y `en-US.json`). **[G]** = voz de porty-growth-lead; **[C]** = revisión de porty-compliance. Borradores:

| Clave | es-ES | en-US |
|---|---|---|
| `binance_screenshot_exit` **[G]** | Mientras tanto, traela con una captura | Meanwhile, bring it in with a screenshot |
| `snaptrade_screenshot_exit` **[G]** | Mientras tanto, traela con un extracto o una captura | Meanwhile, bring it in with a statement or a screenshot |
| `diagnosis_sync_title` **[G][C]** | Que se actualice sola | Keep it up to date on its own |
| `diagnosis_sync_detail_locked` **[G][C]** | Conectá tu bróker y Porty la mantiene al día. Viene con Premium. | Connect your broker and Porty keeps it current. Comes with Premium. |
| `diagnosis_sync_detail` **[G]** | Conectá tu bróker y Porty la mantiene al día. | Connect your broker and Porty keeps it current. |
| `diagnosis_push_title` **[G][C]** | ¿Te aviso el sábado? | Want a heads-up on Saturday? |
| `diagnosis_push_detail` **[G][C]** | Te cuento qué pasó en tu semana. | I'll tell you how your week went. |
| `push_prompt_title_diagnosis` / `push_prompt_body_diagnosis` **[G][C]** | El resumen de tu semana, el sábado / Un aviso por semana con cómo le fue a tu cartera. Lo apagás cuando quieras. | Your week, every Saturday / One notification a week with how your portfolio did. Turn it off anytime. |
| `assistant_quota_nudge` **[G]** | Te quedan {remaining} consultas este mes. Con {plan} tenés {count}. | You have {remaining} queries left this month. {plan} gives you {count}. |
| `assistant_quota_nudge_cta` | Ver planes | See plans |
| `paywall_title_quota_low` / `paywall_subtitle_quota_low` **[G][C]** | Te quedan pocas consultas / Con Premium tenés {count} por mes y preguntás por cualquier ticker. | You're running low on queries / Premium gives you {count} a month and any ticker you want. |
| `paywall_quota_returns` | Tus consultas vuelven el {date}. | Your queries come back on {date}. |

`{plan}` = título del plan siguiente (`paywall_premium_title` / `paywall_gold_title`); `{count}` = `PlanMatrix.of(nextTier).monthlyQueries`. Ningún número escrito en el texto.

### 3.5 Eventos nuevos en `product_events`

Se agregan a `enum ProductEvent` (flutter-dev), `once: false`:

| Evento | Cuándo | `props` |
|---|---|---|
| `nudge_tapped` | toque en la salida de captura | `{"surface": "broker_locked_binance" \| "broker_locked_snaptrade", "action": "screenshot"}` |
| `broker_connect_result` | al terminar un intento de conectar (eToro, Binance, SnapTrade) | `{"broker": "etoro" \| "binance" \| "snaptrade", "result": "ok" \| "plan_required" \| "limit" \| "cancelled" \| "error"}` |
| `push_opt_in` | al cerrar `PushPermissionSheet` **si se mostró** (todas las razones, no solo diagnóstico) | `{"source": "diagnosis", "result": "granted" \| "denied" \| "dismissed"}` |

`push_opt_in.source` = `PushPromptReason.name` (`priceAlert`, `weeklyReport`, `etoro`, `settings`, `diagnosis`). `dismissed` = "Ahora no"; `denied` = rechazó el diálogo del sistema.

Las filas del diagnóstico y la línea de cuota se miden con los eventos de la spec anterior: `paywall_viewed{source: diagnosis_sync | quota_soft}` → `purchase_result`. Denominadores: `diagnosis_seen` (3b), `onboarding_finished{exit: connectBroker}` (3a), `ai_usage_monthly.queries_used >= 15` en Free (3c).

---

## 4. Tareas por dueño

Dos dueños nunca tocan el mismo archivo. Traducciones: solo flutter-dev.

### porty-backend-dev (independiente)

| Archivo | Qué |
|---|---|
| `supabase/migrations/20261102120200_conversion_nudge_flags.sql` (nuevo) | Las 3 filas (§3.1) |

Es la única tarea de backend. Puede ir en el mismo `db push` que la spec anterior.

### porty-flutter-dev (después de la fase C de la spec anterior en `subscription_paywall_sheet.dart`; lo demás puede arrancar después de su fase A)

**Primero, piezas que necesita assistant-dev** (commit chico, avisa al terminar): `PaywallReason.quotaLow`, `PaywallSource.quotaSoft`, `ConversionFlags.quotaNudge` + `quotaNudgeEnabledProvider`, `PlanSpec.quotaNudgeAtRemaining`, `PlanMatrix.nextTier`, claves `assistant_quota_nudge*`.

| Archivo | Qué |
|---|---|
| `lib/features/subscription/config/conversion_flags.dart` | 3 flags + providers (§3.1) |
| `lib/features/subscription/config/paywall_source.dart` | `diagnosisSync`, `quotaSoft` |
| `lib/features/subscription/providers/subscription_provider.dart` | `PaywallReason.quotaLow` |
| `lib/features/subscription/ui/subscription_paywall_sheet.dart` | Título/subtítulo `quotaLow`, medidor en `quotaLow`, `paywall_quota_returns` |
| `lib/domain/subscription/plan_matrix.dart` | `quotaNudgeAtRemaining`, `nextTier` |
| `lib/features/product_events/data/product_events.dart` | 3 eventos (§3.5) |
| `lib/features/binance/view/binance_screen.dart` | Salida de captura (3a) + `broker_connect_result` |
| `lib/features/snaptrade/view/snaptrade_screen.dart` | Salida de captura (3a) + `broker_connect_result` |
| `lib/features/etoro/view/etoro_connection_screen.dart` | `broker_connect_result` |
| `lib/features/portfolio_diagnosis/view/portfolio_diagnosis_screen.dart` | Filas sync y push (3b) |
| `lib/features/notifications/view/push_permission_sheet.dart` | `PushPromptReason.diagnosis` + textos + `push_opt_in` |
| `assets/translations/es-ES.json`, `assets/translations/en-US.json` | §3.4 |
| `test/features/binance/binance_test.dart`, `test/features/snaptrade/snaptrade_test.dart`, `test/features/portfolio_diagnosis/portfolio_diagnosis_screen_test.dart`, `test/features/notifications/notifications_widgets_test.dart`, `test/features/subscription/paywall_sheet_test.dart`, `test/domain/subscription/plan_matrix_test.dart` | §5 |

### porty-assistant-dev (después de las "piezas" de flutter-dev)

| Archivo | Qué |
|---|---|
| `lib/features/assistant/models/portfolio_qa_message.dart` | `quotaNudgeRemaining` |
| `lib/features/assistant/services/quota_nudge_memory.dart` (nuevo) | Una vez por mes UTC y por usuario (SharedPreferences) |
| `lib/features/assistant/providers/assistant_provider.dart` | Después del `refresh` del turno, decidir y marcar el mensaje (§3.4, 3c) |
| `lib/features/assistant/view/widgets/assistant_quota_nudge.dart` (nuevo) | La línea + link "Ver planes" |
| `lib/features/assistant/view/assistant_screen.dart` | Renderizar debajo de la respuesta; abrir el paywall `quotaLow` / `quota_soft` |
| `test/features/assistant/...` (provider y widget) | §5 |

No toca prompt, reglas, tools, catálogo ni widgets del catálogo.

### Orden

`backend` (cuando sea) ∥ `flutter: piezas` → `assistant` ∥ `flutter: pantallas`. Todo después de la spec anterior en el paywall.

---

## 5. Criterios de aceptación

`flutter test test/features/binance test/features/snaptrade test/features/portfolio_diagnosis test/features/notifications test/features/subscription test/features/assistant test/features/genui_core test/security`; `flutter analyze` sin warnings nuevos.

**3a**
1. Free con `brokerScreenshotExitEnabledProvider = true`: en Binance y en SnapTrade se ven "Ver planes" (primero) y la salida; tocarla registra `nudge_tapped{surface, action: screenshot}` y navega a `StatementImportRouter.routeName`.
2. Con el flag en `false`, o con un plan que incluye `brokerSync`: la salida no aparece.
3. "Ver planes" abre el paywall con `binance_connect` / `snaptrade_connect` (sin cambios respecto de la spec anterior).
4. Un intento de conexión que vuelve con `*_plan_required` registra `broker_connect_result{result: plan_required}`; uno exitoso, `ok`.

**3b**
5. Flag prendido, Free, cartera sin posiciones importadas: la fila sync abre el paywall `brokerSync` con `diagnosis_sync`. Premium: navega a `ConnectBrokerRouter` sin paywall. Con alguna posición importada: no aparece.
6. Con permiso `notDetermined` aparece la fila push; tocarla abre `PushPermissionSheet` con los textos de `diagnosis`; aceptar o "Ahora no" registra `push_opt_in{source: diagnosis, result}`. Con `unavailable` o ya decidido: no aparece.
7. Flag apagado: el diagnóstico es idéntico al de hoy (golden o búsqueda de textos).
8. El diagnóstico sigue mostrando todos los hallazgos y preguntas en Free.

**3c**
9. Provider: Free con 6 → 5 restantes tras un turno y flag prendido: el mensaje del turno tiene `quotaNudgeRemaining = 5`; el siguiente turno del mismo mes, no; otro mes (reloj fake), sí de nuevo. Con flag apagado, en Premium/Gold, en 0 o con turno cortado por paywall: no.
10. Widget: la línea muestra "Te quedan 5 consultas este mes. Con Premium tenés 500." (números de `PlanMatrix`) y "Ver planes" abre el paywall `quotaLow` con `quota_soft`, que registra `paywall_viewed{source: quota_soft}` y muestra el medidor.
11. Paywall `quotaExceeded` el 15/11 (reloj fake) muestra "Tus consultas vuelven el 1 de diciembre." (y "December 1" en inglés); el 31/12, "1 de enero".
12. `flutter test test/security/system_prompt_allowlist_test.dart` verde **sin** `UPDATE_PROMPT_ALLOWLIST`.

**Backend**
13. `supabase db reset` local aplica la migración dos veces sin error y deja las 3 filas en `percent: 0`.

**Humo** (porty-qa-engineer): con un usuario en `users` de los 3 flags, recorrer las tres superficies en iOS y Android y verificar las filas en `product_events`; capturas para porty-ui-reviewer de la pantalla de Binance bloqueada, el final del diagnóstico y la línea de cuota (claro y oscuro).

---

## 6. Riesgos y decisiones

**Decisiones**
- **Salida a `StatementImportRouter` sin parámetro de "captura"**: la pantalla ya ofrece las tres formas y el CSV de muchos brókers de SnapTrade es gratis; un parámetro nuevo no suma.
- **"Sin brókers conectados" se decide por `PositionSource.hasImported`** de las posiciones de la Home, no por `portfolioLoadMethodProvider` (que se limpia al registrar `portfolio_loaded`) ni cargando los tres providers de brókers.
- **Premium en la fila sync va a conectar, no al paywall**: ya lo tiene; venderle lo que pagó sería ruido.
- **`force: true` en el pedido de push del diagnóstico**: lo pide un toque explícito; la política de insistencia es para pedidos que ofrece la app.
- **Aviso de cuota por capacidad** (`quotaNudgeAtRemaining` en `PlanSpec`), no `if (tier == free)`. "Una vez por mes" se guarda en el teléfono: si cambia de teléfono, lo puede ver dos veces en el mes. Aceptable para una línea.
- **Sin eventos de impresión** de las filas nuevas: los denominadores ya existen (§3.5). Se agregan en diciembre con `locked_feature_shown` si hace falta.
- **Interruptores en 0**: se prenden con el release publicado, en un día conocido, para que la lectura antes/después tenga un corte claro.

**Riesgos**
- En Free, leer una captura gasta 1 consulta. La salida puede empujar al usuario hacia la cuota; el guardarraíl es la retención Free D7. Si molesta, se apaga el flag.
- Las preguntas del diagnóstico y la fila sync compiten por atención; se mide `diagnosis_question` antes/después para ver si cae.
- Sin F0 (Firebase/APNs) la fila push nunca aparece: 3b mide solo el puente al pago.

**Textos para porty-compliance:** las claves **[C]** de §3.4 (fila sync, fila y hoja de push, paywall `quotaLow`). Esta spec no agrega texto de renovación: el paywall ya muestra los términos de la spec anterior en todos los motivos, incluido `quotaLow`.

**Toca el prompt o el catálogo del chat:** **no**. La línea de cuota la arma la app fuera del catálogo; no hace falta regenerar la allowlist ni desplegar `ai-chat`.

**Necesita OK del usuario**
1. `db push` de `20261102120200_conversion_nudge_flags.sql` (junto con las de la spec anterior).
2. Prender los 3 interruptores en producción cuando salga el release (SQL en §3.1).
3. Publicación del release (va en el release 1 junto con la spec anterior).
4. Texto final de compliance en las claves [C]. (Los productos anuales y el deploy de `revenuecat-webhook` son de la spec anterior; esta no los necesita.)
