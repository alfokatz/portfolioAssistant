# Brief: paywall medible y aprobable por las tiendas

**Fecha:** 2026-11-02 · **Autor:** porty-product-owner · **Estado:** listo para porty-architect · **Apuesta #1 de noviembre** (`docs/product/roadmap.md`)

## 1. Problema

Queremos más usuarios que paguen y **no podemos ver dónde se pierden**. Tres problemas, con su evidencia:

1. **El tramo paywall → compra no existe en los datos.** `PaywallSourceLog` guarda solo en memoria y en `debugPrint`; `SubscriptionPaywallSheet._purchase` ve el resultado (éxito, cancelado, error) y no lo registra; ~la mitad de las aperturas no pasan `source`; el webhook de RevenueCat descarta precio, tienda, tipo de período y entorno (sandbox o producción). *Evidencia: lectura del código, `docs/business/metrics/2026-11-02-embudo-a-pago.md` §2 y §4; lo confirman growth y monetización.* Sin esto, las apuestas #2 a #5 se evalúan a ciegas.
2. **Riesgo de rechazo en la tienda.** El paywall muestra el precio por mes pero no los términos de renovación automática ni links a Términos y Privacidad junto al botón. Apple (3.1.2 y la guía de suscripciones) lo exige. La próxima revisión es la que trae el plan anual: un rechazo frena el mes entero. *Evidencia: auditoría de monetización §2.7. Pendiente de confirmar por porty-compliance.*
3. **El paywall cuenta mal lo que vende.** El punto de entrada más intencional (Ajustes → "Mejorar plan") y el tope de 10 posiciones usan un copy heredado ("Modo no disponible… desbloquear modos"), cuando los modos ya no existen. Cada plan abre con "500 / 1000 consultas", o sea: vende el número y no lo que el usuario gana. El medidor "3/20 consultas" aparece aunque el motivo sea un análisis Gold. *Evidencia: auditoría de monetización §2.2. Que esto baje la conversión es intuición, no un dato.*

## 2. Para quién

Todos los usuarios que ven un paywall: Free (casi todos) y Premium que ve un motivo Gold. Usuarios nuevos y recurrentes. El cambio visible es chico; el valor es sobre todo para el equipo (poder decidir) y para no frenar la publicación.

## 3. Métrica de éxito y cómo se mide

| Métrica | Meta | Cómo |
|---|---|---|
| Aperturas de paywall con `source` específico (no el `reason` genérico) | 100 % | `product_events` donde `event = 'paywall_viewed'`, agrupado por `props->>'source'` |
| Compras con `source` atribuido | ≥ 95 % de las compras de producción | `purchase_result{result: success}` cruzado con `subscription_events` (`environment = 'PRODUCTION'`) y el atributo `paywall_source` de RevenueCat |
| Tabla "paywall visto → compra, por `source`" | Disponible el 23/11 | Consulta de porty-data-analyst sobre las dos tablas |
| Release aprobado por Apple y Google sin rechazo por 3.1.2 | Sí | Resultado de la revisión |
| Conversión paywall → compra | **Sin meta este mes**: es la línea de base | Primera lectura el 23/11 |

## 4. Alcance mínimo

**Medición (app):**
- Eventos en `product_events` (tabla existente, con `ProductEvents.log`; sin tabla nueva de paywall):
  - `paywall_viewed{reason, source, tier, visible_tiers, queries_used, queries_limit}`;
  - `paywall_plan_tapped{tier, period, source}`;
  - `purchase_result{tier, period, source, result: success|cancelled|failed|not_configured}`, también para Restaurar;
  - `paywall_dismissed{source, seconds_open}`.
- `source` **obligatorio** en `SubscriptionPaywallSheet.show`: se completa en las ~10 aperturas que hoy no lo pasan (`chat_quota`, `chat_turn_locked_<feature>`, `add_position_limit`, `snaptrade_connect`, `binance_connect`, `watchlist`, `allocation`, `statement_import`, `settings`…). Con un test que falle si alguna lo omite.
- Antes de comprar: `paywall_source` como atributo del suscriptor en RevenueCat.
- Eventos que necesitan las apuestas #3 y #5, de una línea cada uno, en la misma pasada: `broker_connect_result{broker, result}`, `push_opt_in{source}`, `weekly_report_opened{mode}`, `app_opened` (una vez por día). Si no entran en el tamaño, viajan con la apuesta que los usa.

**Medición (servidor):**
- Tabla `subscription_events`: el webhook guarda el evento crudo antes de recalcular el plan (`event_type`, `product_id`, `store`, `period_type`, `price`, `currency`, `environment`, `event_at`).
- `product_funnel` suma `min_to_first_paywall` y `min_to_purchase`.

**Lo que ve el usuario:**
- Debajo de los botones: "Se renueva cada {mes/año} a {precio}. Cancelás cuando quieras desde {App Store / Google Play}." y links a Términos y Privacidad. **Texto final de porty-compliance.**
- Títulos por motivo en la voz de Porty, que digan qué gana y no qué le falta: `plans` (Ajustes: "Elegí tu plan"), `positionLimit`, `simulations`, `goals`, `allocationPlan`. Reemplazan al `modeLocked` genérico. Se corrige `settings_upgrade_coming_soon` ("suscripciones Pro").
- El medidor de uso aparece solo cuando el motivo es la cuota. "N consultas por mes" pasa a texto secundario.
- El orden de los planes **no cambia** (Gold primero como hoy).

## Fuera de alcance

- Plan anual (apuesta #2: va justo después, sobre el mismo paywall).
- Cambiar el orden de planes según el motivo (diciembre, con datos).
- Prueba de Gold, cambios de precio o de cuotas.
- Paywalls nuevos (#3 y #4).
- `locked_feature_shown` (impresiones de teasers): diciembre.
- Dashboard o tablero: este mes alcanza con las consultas SQL de porty-data-analyst.
- SDK de analytics de terceros o atribución de instalaciones.

## 5. Impacto en negocio

- **Conversión a pago:** directo, chico (copy y claridad de términos; no hay dato que lo cuantifique). **Indirecto, alto:** sin esto no se puede saber si #2–#5 funcionan, ni decidir la prueba en diciembre con datos.
- **Riesgo evitado:** un rechazo por 3.1.2 trabaría el anual y todo lo que sale en el release 1.
- **Confianza:** los términos claros responden a lo que más daña a la competencia ("me cobró", reembolsos). Encaja con *trustworthy*.
- **Costo:** ninguno de IA; filas chicas en dos tablas.
- **Privacidad:** los eventos no llevan datos personales ni montos de la cartera; `subscription_events` guarda precio del producto, no datos de pago. Lo confirma porty-security-reviewer.

## 6. Criterios de aceptación de usuario

1. Desde cualquier paywall, el usuario ve antes de comprar cada cuánto se renueva, a qué precio (el de la tienda, localizado) y que cancela desde la tienda, con links a Términos y Privacidad que abren.
2. En Ajustes → "Mejorar plan", el título es neutral ("Elegí tu plan") y no menciona "modos" ni "Pro".
3. Al llegar al tope de 10 posiciones, el título habla de cargar toda la cartera, no de "modos".
4. Si el paywall se abre por un análisis Gold, no aparece el medidor de consultas; si se abre por cuota agotada, sí.
5. "Restaurar compras" sigue visible en todos los paywalls.
6. Comprar, cancelar la compra o que falle se comporta igual que hoy para el usuario (no se agregan pasos).
7. En el lado del equipo: cada apertura, toque, compra y cierre del paywall aparece en `product_events` con su `source`; cada evento de RevenueCat aparece en `subscription_events` con precio, tienda y entorno.

## 7. Prioridad (RICE)

| R | I | C | E | Score |
|---|---|---|---|---|
| 60 % de la cohorte (supuesto: quienes ven al menos un paywall) | 1 (habilita + evita rechazo) | 90 % | 3 días-persona | **18** |

Es #1 del mes. Contra el backlog: el plan anual (16,8) va sobre este mismo paywall y necesita los términos de renovación; la prueba de Gold (~18,7) no se puede leer sin esta medición y además requiere que el usuario levante su decisión del 26/10. Contra `docs/backlog/notificaciones-y-alertas-de-precio.md`: ya implementado, no compite.

## 8. Dependencias y dueños

- porty-architect: spec técnica de #1 y #2 juntas (mismo archivo: `subscription_paywall_sheet.dart`).
- porty-flutter-dev: paywall, eventos, `source` obligatorio, títulos.
- porty-backend-dev: `subscription_events` (migración nueva), webhook, `product_funnel`.
- porty-compliance: texto de renovación y de títulos.
- porty-security-reviewer: webhook y tabla nueva (RLS: sin lectura desde la app).
- porty-qa-engineer: humo de compra en sandbox (iOS y Android) con eventos verificados.
- porty-data-analyst: consulta de lectura para el 23/11.
- Usuario: aprobar migración y despliegue del webhook; aprobar publicación.
