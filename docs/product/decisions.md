# Decisiones de producto

Una línea por decisión. Formato: fecha · decisión · por qué · quién decide.

- 2026-10-26 · Aha completo en Free y primera importación de eToro gratis; sin prueba de Gold por ahora · `docs/superpowers/plans/2026-10-26-aha-moment.md` · usuario.
- 2026-11-02 · Foco de noviembre: el tramo aha → primer pago; no se agregan features nuevas · el aha ya es rápido y gratis, la pérdida está después y no se ve · product-owner.
- 2026-11-02 · Apuesta #1 = paywall medible y aprobable (eventos + `subscription_events` + términos de renovación) · sin medición nada se evalúa y sin términos hay riesgo de rechazo Apple 3.1.2 · product-owner.
- 2026-11-02 · Los eventos de paywall van a `product_events` con los nombres del doc de data (`paywall_viewed`, `paywall_plan_tapped`, `purchase_result`, `paywall_dismissed`); no se crea `paywall_events` · una sola fuente de eventos · product-owner.
- 2026-11-02 · `source` obligatorio en toda apertura de paywall; cada paywall nuevo nace con su `source` propio · permite atribuir compras con varios cambios a la vez · product-owner.
- 2026-11-02 · Sin A/B en noviembre; cambios detrás de `app_config` y lectura por cohorte antes/después · ~3.800 usuarios por brazo hacen falta y no los tenemos · product-owner.
- 2026-11-02 · La prueba de Gold no entra en noviembre; la decisión del 26/10 sigue vigente · es del usuario, es el único cambio global (ensucia la lectura de lo demás) y no hay línea de base · product-owner, se propone al usuario para diciembre.
- 2026-11-02 · Si se hace prueba en diciembre, se recomienda Gold (que incluye Premium), 7 días sin tarjeta, tope de 100 consultas y búsquedas al nivel de Premium, un solo brazo · el costo queda acotado (~US$0,70 peor caso, supuesto) y el usuario ve toda la escalera · lo decide el usuario.
- 2026-11-02 · El margen negativo de Gold no frena regalar Gold con tope; sí obliga a vigilar el p99 de costo de Gold pago (Q4) · el riesgo está en búsquedas al tope sin caché, no en una prueba acotada · product-owner.
- 2026-11-02 · Plan anual en noviembre (apuesta #2); precio propuesto 10× el mensual · todos los comparables lo tienen y protege contra el churn de apps con IA · el precio lo decide el usuario.
- 2026-11-02 · El orden de planes según motivo (Premium primero en motivos Premium) pasa a diciembre · necesita medir ARPU por expuesto, no solo conversión · product-owner.
- 2026-11-02 · Degustación de Premium: 3 consultas de mercado por mes en Free, sin cortar el turno, detrás de interruptor · la escalera está invertida (Gold se prueba, Premium no) · requiere aprobación del usuario porque cambia lo que incluye Free.
- 2026-11-02 · Salida gratis ("traela con una captura") en las pantallas bloqueadas de Binance y SnapTrade; Binance gratis la primera vez queda para diciembre · cerrar el callejón es S y no regala nada pago · product-owner (la variante gratis la decide monetización + usuario).
- 2026-11-02 · Puente al pago al final del diagnóstico: una fila tranquila, sin modal; el diagnóstico sigue completo en Free · respeta la decisión del 26/10 y aprovecha el pico de confianza · product-owner.
- 2026-11-02 · Aviso de cuota a las 15/20 y fecha de renovación en el paywall de cuota; el límite de 20 no cambia · protege la retención Free sin tocar costos · product-owner.
- 2026-11-02 · Informe semanal completo las primeras 3 semanas (N en `app_config`) · una degustación no forma hábito; costo ~US$0,004 por informe · product-owner.
- 2026-11-02 · No se tocan precios ni cuotas en noviembre · faltan 4–8 semanas de `ai_usage_monthly_stats` y eventos de paywall · product-owner.
- 2026-11-02 · Posicionamiento frente al MCP de IOL: multi-bróker + números exactos con fuente + informe semanal, no "chat que ve tu cartera" · el chat sobre la cartera se regala (IOL, Public, Robinhood) · product-owner; mensaje para porty-marketing-lead.
- 2026-11-02 · Rendimiento real en USD (MEP/CCL) contra benchmark, con fuente: discovery en diciembre · es la mejor oportunidad de diferenciación pero es L · product-owner.
- 2026-11-02 · El borrado de cuenta en la app entra como condición para publicar el release 1 (ítem 0, fuera de RICE) · Apple 5.1.1(v) y Google Play lo exigen; hoy es un rechazo seguro (compliance H1) · product-owner.
- 2026-11-02 · El release 1 no se envía sin borrado de cuenta y sin Términos/Privacidad verificados con la marca Porty (H2) · cualquier envío sin eso se rechaza · product-owner; Términos y Privacidad los publica el usuario.
- 2026-11-02 · `subscription_events.user_id` con `on delete cascade` en este release; `set null` cuando se cumplan las 3 condiciones de compliance · más seguro y con poco volumen no se pierde nada · product-owner, con arquitecto y compliance.
- 2026-11-02 · Si falla el borrado, por defecto se muestra el error honesto de falla parcial con un mail de contacto; "no se borró nada" solo si el arquitecto garantiza que no quedan brókers desconectados · no le decimos al usuario algo que puede no ser cierto · product-owner; textos de compliance §6.
- 2026-11-02 · El aviso de suscripción al borrar aparece con cualquier entitlement activo, aunque esté cancelado, y nombra la tienda donde se compró · mostrarlo de más cuesta poco; no mostrarlo termina en un cobro después del borrado · product-owner + compliance.
- 2026-11-02 · Si el backend no da abasto por el borrado, la apuesta #5 pasa de S3 a S4 · igual se lee en diciembre · product-owner.
- 2026-11-02 · Referidos y tarjeta compartible: después de diciembre y con compliance antes · con poco tráfico el loop rinde poco · product-owner.
