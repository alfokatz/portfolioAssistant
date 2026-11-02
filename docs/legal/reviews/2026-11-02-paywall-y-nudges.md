# Revisión de compliance: paywall medible + anual y momentos sin callejones

**Fecha:** 2026-11-02 · **Autor:** porty-compliance (no es asesoramiento legal)
**Specs:** `docs/superpowers/specs/2026-11-02-paywall-medible-y-anual.md` (§3.7, §3.8, §6) y `docs/superpowers/specs/2026-11-02-sin-callejones.md` (§3.4)
**Veredicto:** ok con cambios en los textos. **Bloquea el envío a tiendas** por algo de fuera de los textos: no hay borrado de cuenta en la app (H1). Además, las páginas de Términos y Privacidad no se pudieron verificar (H2).

Normas que usé:
- Apple App Store Review Guidelines 3.1.2, 4.5.4 y 5.1.1(v): https://developer.apple.com/app-store/review/guidelines/ (leídas hoy). 3.1.2(c) remite al Schedule 2 del Apple Developer Program License Agreement: título, duración, precio y links a Términos y Privacidad dentro de la app. Ver https://developer.apple.com/app-store/subscriptions/
- Borrado de cuenta en Apple: https://developer.apple.com/support/offering-account-deletion-in-your-app/
- Google Play, política de suscripciones: https://support.google.com/googleplay/android-developer/answer/9900533. **No la pude abrir**: el host no resuelve desde esta sesión. La cito de memoria y hay que confirmarla.
- Google Play, borrado de cuenta: https://support.google.com/googleplay/android-developer/answer/13327111 (tampoco la pude abrir)
- Ley 24.240 de Defensa del Consumidor, art. 4 (información cierta, clara y detallada): https://servicios.infoleg.gob.ar/infolegInternet/anexos/0-4999/638/texact.htm
- Ley 25.326 de Protección de Datos Personales, arts. 4.7 y 16: https://servicios.infoleg.gob.ar/infolegInternet/anexos/60000-64999/64790/texact.htm
- GDPR, art. 17 y considerando 26: https://eur-lex.europa.eu/eli/reg/2016/679/oj

---

## 1. Textos finales aprobados (claves [C])

flutter-dev usa estos textos tal cual. Mantienen la voz rioplatense que ya tiene `es-ES.json`. Ningún texto BLOQUEA, así que no le mandé mensaje a flutter-dev.

### Spec paywall medible y anual

| Clave | es-ES (final) | en-US (final) | Estado |
|---|---|---|---|
| `paywall_renews_line` | Se renueva cada {period} a {price}. Cancelás cuando quieras. | Renews every {period} at {price}. Cancel anytime. | Aprobado sin cambios |
| `paywall_terms_block` | El cobro se hace en tu cuenta de {store} al confirmar la compra. La suscripción se renueva automáticamente por el mismo período, salvo que la canceles al menos 24 horas antes de que termine el período actual. La gestionás y la cancelás desde los ajustes de tu cuenta de {store}. Borrar la app o tu cuenta de Porty no cancela la suscripción. | Payment is charged to your {store} account at confirmation of purchase. The subscription automatically renews for the same period unless canceled at least 24 hours before the end of the current period. Manage or cancel it in your {store} account settings. Deleting the app or your Porty account doesn't cancel the subscription. | CORREGIR (H3) |
| `paywall_annual_savings` | Ahorrás {percent} % frente al mensual | Save {percent}% vs. monthly | CORREGIR (H4) |
| `paywall_title_plans` | Elegí tu plan | Choose your plan | Aprobado |
| `paywall_subtitle_plans` | Premium para mirar el mercado. Gold para entender el porqué. | Premium to follow the market. Gold to understand the why. | Aprobado |
| `paywall_title_position_limit` | Traé toda tu cartera | Bring your whole portfolio | Aprobado |
| `paywall_subtitle_position_limit` | Free llega a {limit} posiciones. Con Premium cargás todas y Porty la mira completa. | Free covers up to {limit} positions. With Premium you add them all and Porty sees the full picture. | Aprobado |
| `paywall_title_simulations` | Probá escenarios con tus números | Try scenarios with your own numbers | CORREGIR (H5) |
| `paywall_subtitle_simulations` | Con Premium, Porty simula cuánto podría crecer un aporte. Es una estimación educativa: no es una recomendación ni una garantía. | With Premium, Porty simulates how a contribution could grow. It's an educational estimate, not a recommendation or a guarantee. | CORREGIR (H5) |
| `paywall_title_goals` | Ponele número a tu meta | Put a number on your goal | Aprobado |
| `paywall_subtitle_goals` | Con Premium, Porty calcula cuánto tendrías que aportar para llegar y te muestra si vas atrasado. | With Premium, Porty works out how much you'd need to contribute to get there and shows you if you're falling behind. | CORREGIR (H6) |
| `paywall_title_allocation_plan` | Armá tu plan de cartera | Build your portfolio plan | Aprobado |
| `paywall_subtitle_allocation_plan` | Con Premium definís cuánto querés en cada cosa y Porty hace la cuenta de cómo repartir tu próximo aporte. | With Premium you set your targets and Porty does the math on how to split your next contribution. | CORREGIR (H7) |
| `paywall_title_mode_locked` | Esto viene con Premium | This comes with Premium | Aprobado |
| `paywall_subtitle_mode_locked` | Mejorá tu plan para usar esta función. | Upgrade your plan to use this feature. | Aprobado |

### Spec sin callejones

| Clave | es-ES (final) | en-US (final) | Estado |
|---|---|---|---|
| `diagnosis_sync_title` | Que se actualice sola | Keep it up to date on its own | Aprobado |
| `diagnosis_sync_detail_locked` | Conectá un bróker compatible y Porty la mantiene al día. Viene con Premium. | Connect a supported broker and Porty keeps it current. Comes with Premium. | CORREGIR (H8) |
| `diagnosis_push_title` | ¿Te aviso el sábado? | Want a heads-up on Saturday? | Aprobado |
| `diagnosis_push_detail` | Te cuento qué pasó en tu semana. | I'll tell you how your week went. | Aprobado |
| `push_prompt_title_diagnosis` | El resumen de tu semana, el sábado | Your week, every Saturday | Aprobado |
| `push_prompt_body_diagnosis` | Los sábados te llega cómo le fue a tu cartera en la semana. Lo apagás cuando quieras. | Every Saturday you'll get how your portfolio did that week. Turn it off anytime. | CORREGIR (H9) |
| `paywall_title_quota_low` | Te quedan pocas consultas | You're running low on queries | Aprobado |
| `paywall_subtitle_quota_low` | Con Premium tenés {count} por mes y consultás también tickers fuera de tu cartera. | Premium gives you {count} a month, plus tickers outside your portfolio. | CORREGIR (H10) |

Esta clave no lleva [C], pero para mantener la coherencia con H8 sugiero `diagnosis_sync_detail`: "Conectá un bróker compatible y Porty la mantiene al día." / "Connect a supported broker and Porty keeps it current."

Lo que revisé y está bien: el aviso de cuota no es urgencia falsa. Aparece una sola vez por mes, solo cuando de verdad quedan entre 1 y 5 consultas, no tiene contador ni modal y el número sale de `subscriptionProvider`. `paywall_quota_returns` también está bien: el reinicio es a medianoche UTC, así que en Argentina las consultas vuelven el 30 a las 21 h, antes de la fecha que se muestra. Eso juega a favor del usuario.

---

## 2. Hallazgos

[BLOQUEA] `settings_screen.dart:211-223` (`_onDeleteAccount`): borrar la cuenta solo muestra "La eliminación de cuenta estará disponible pronto"
Por qué: Apple 5.1.1(v) dice "If your app supports account creation, you must also offer account deletion within the app" (https://developer.apple.com/app-store/review/guidelines/). Google Play exige borrado en la app y también un link web (https://support.google.com/googleplay/android-developer/answer/13327111). Es un rechazo en cualquier envío y no depende de estas specs. Además, sin borrado real, la pregunta sobre `on delete` (§3) es teórica.
Texto propuesto: el flujo de borrado (backend + app) tiene que, en este orden: (1) avisar "Si tenés una suscripción activa, cancelala desde {store}: borrar tu cuenta no la cancela."; (2) borrar el usuario en RevenueCat; (3) borrar `auth.users`.
Revisión humana: no. Se lo avisé a porty-product-owner porque cambia el alcance del release.

[BLOQUEA para el envío, no para construir] H2. `portfolioai.app/terms` y `/privacy` no se pudieron verificar
Por qué: Apple 3.1.2(c) más el Schedule 2 del DPLA exigen links funcionales a Términos y Privacidad. WebFetch no resolvió el dominio porque está fuera de la red de esta sesión. `docs/porty-rename-checklist.md:83` además avisa que esas páginas probablemente dicen "PortfolioAI". En el repo no hay borrador de Términos ni de Privacidad.
Texto propuesto: §4 (cláusula de suscripciones para Términos y párrafo para Privacidad). Hasta que esté publicada, en App Store Connect hay que poner el link al EULA estándar de Apple (https://www.apple.com/legal/internet-services/itunes/dev/stdeula/) en la descripción o en el campo EULA, y cargar la Privacy Policy URL.
Revisión humana: sí. El usuario tiene que abrir las dos URLs y un abogado tiene que validar los Términos completos.

[CORREGIR] H3. `paywall_terms_block`: el borrador cumple 3.1.2, pero le faltaban dos cosas
Por qué: (a) Apple pide avisar que borrar la cuenta no cancela la facturación (https://developer.apple.com/support/offering-account-deletion-in-your-app/), y es la queja de soporte más común en apps de suscripción. (b) "Desde {store}" es ambiguo: la cancelación está en los ajustes de la cuenta de la tienda. Saqué "se renueva sola" para usar "automáticamente", que es la palabra que esperan los revisores. No puse "al mismo precio" porque las tiendas permiten subas de precio con aviso. La regla de las 24 horas es de Apple, pero en Google Play también se cumple, porque cancelar antes siempre evita el cobro.
Texto propuesto: §1.
Revisión humana: no.

[CORREGIR] H4. `paywall_annual_savings`: "Ahorrás 16 %" sin decir contra qué
Por qué: la Ley 24.240 art. 4 pide información clara, y Apple 3.1.2(a) y la política de suscripciones de Play prohíben las ofertas engañosas. El cálculo de la spec es correcto: floor, misma moneda y se oculta si es menor a 1. Solo falta decir con qué se compara.
Texto propuesto: §1. Condición: si algún día hay ofertas introductorias en los anuales, el ahorro tiene que calcularse contra el precio normal o no mostrarse.
Revisión humana: no.

[CORREGIR] H5. `paywall_*_simulations`: "con datos reales" sugiere que la proyección es real
Por qué: la simulación usa un rendimiento esperado supuesto ("Simulación con un rendimiento esperado... No es una garantía", `goal_plan_note`), no un dato real. Presentar una proyección como "real" se acerca a prometer un rendimiento.
Texto propuesto: §1.
Revisión humana: no.

[CORREGIR] H6. `paywall_subtitle_goals`: "calcula cuánto aportar" suena a indicación, y "te avisa" no es cierto
Por qué: no hay push de metas. El atraso se muestra en el inbox de la app (`porty_insights_builder.dart`, `GoalProgressStatus.behind`). Los claims tienen que poder verificarse.
Texto propuesto: §1.
Revisión humana: no.

[CORREGIR] H7. `paywall_subtitle_allocation_plan`: "Porty te dice cómo repartir el próximo aporte" se lee como recomendación personalizada de compra
Por qué: es la línea entre información y asesoramiento. El disclaimer aprobado de la feature ya dice "Es tu plan: Porty solo hace la cuenta" (`allocation_disclaimer`), y el paywall tiene que decir lo mismo.
Texto propuesto: §1.
Revisión humana: no.

[CORREGIR] H8. `diagnosis_sync_detail_locked`: "Conectá tu bróker" da a entender que cualquier bróker funciona
Por qué: solo se soportan eToro, Binance y los brókers de SnapTrade. Un usuario con un bróker no soportado podría pagar Premium por algo que no puede usar (Ley 24.240 art. 4). "Al día" sí es cierto: la sincronización es diaria (`snaptrade-sync/sync.ts`).
Texto propuesto: §1.
Revisión humana: no.

[CORREGIR] H9. `push_prompt_body_diagnosis`: "Un aviso por semana" no es cierto
Por qué: el permiso del sistema habilita todos los tipos de aviso, y `portfolio_moves`, `earnings` y otros arrancan en `true` (`20261016000100_push_new_kinds.sql`). Prometer un solo aviso por semana describe mal el alcance del consentimiento (Apple 4.5.4). La hoja ya muestra "Elegís qué avisos recibir, uno por uno".
Texto propuesto: §1.
Revisión humana: no.

[CORREGIR] H10. `paywall_subtitle_quota_low`: "cualquier ticker" es un claim absoluto
Por qué: la cobertura depende de los proveedores de datos (Finnhub). Lo que se puede verificar es lo que da `PlanFeature.marketData`: tickers fuera de la cartera.
Texto propuesto: §1.
Revisión humana: no.

[SUGERENCIA] Paywall sin precio (`paywall_price_unavailable`): deshabilitar el CTA si no hay `priceString`
Por qué: 3.1.2(c) pide que el usuario vea el precio antes de suscribirse. Hoy la compra fallaría igual con `package_not_found`, pero un revisor que ve un botón activo sin precio lo puede rechazar.
Revisión humana: no.

[SUGERENCIA] Ajustes: agregar "Gestionar suscripción" con link a la tienda (`https://apps.apple.com/account/subscriptions` y `https://play.google.com/store/account/subscriptions`)
Por qué: Argentina tiene la Resolución SC 316/2018 ("botón de baja") y facilita cumplir la política de Play sobre cómo cancelar. Que aplique a una app que cobra por la tienda es una duda legal.
Revisión humana: sí.

---

## 3. Pregunta 1: `subscription_events.user_id`, ¿`on delete set null` o `cascade`?

**Recomendación: `on delete set null`, con tres condiciones. Sin ellas, `cascade`.**

**Por qué no hace falta `cascade` por motivos contables:** Apple y Google son el *merchant of record*. Porty no le factura al usuario. Le factura a la tienda por el pago agregado, y la documentación respaldatoria son los reportes de pagos de App Store Connect y Play Console, no esta tabla. Así que la excepción por obligación legal (GDPR art. 17.3.b; Ley 25.326 art. 16) **no** justifica guardar estos registros asociados a una persona. La justificación es analítica (ingresos, atribución), y eso solo se sostiene si el registro deja de ser un dato personal.

**Por qué `set null` solo no alcanza:** con `user_id` en null, la fila conserva `event_id` (el id de RevenueCat), timestamps exactos, producto y precio. Con el dashboard de RevenueCat, que lo controla Porty, `event_id` lleva de vuelta al `app_user_id`, que es el uuid de Supabase. Eso es un dato **seudonimizado**, no anonimizado (GDPR considerando 26), y la Ley 25.326 art. 4.7 pide destruir los datos que ya no son necesarios.

**Condiciones para `set null`:**
1. **El borrado de cuenta borra al cliente en RevenueCat** (`DELETE /v1/subscribers/{app_user_id}`, https://www.revenuecat.com/docs/api-v1) antes de borrar `auth.users`. Así `event_id` ya no se puede volver a vincular.
2. **Bug en el webhook (§3.9, paso 1):** si alguien borra la cuenta con la suscripción activa, RevenueCat sigue mandando `RENEWAL`/`EXPIRATION` con el uuid borrado. Si `user_id = app_user_id` porque "es uuid", (a) el insert falla por la FK, el webhook responde 500 y RevenueCat reintenta indefinidamente, y (b) si no fallara, volvería a vincular el registro. `eventRow` o el insert tienen que guardar `null` cuando el uuid no existe en `auth.users`. Esto es para backend-dev y el arquitecto.
3. **Política de privacidad:** declarar que se conservan registros de compra desvinculados de la cuenta para métricas de ingresos (texto en §4.2), y anotarlo en `data-inventory.md` cuando exista.

Si cualquiera de las tres queda para después, usar `cascade` ahora. Es más seguro, y pasar de `cascade` a `set null` cuesta lo mismo más adelante.

Revisión humana: **sí**. Un contador o abogado tiene que confirmar que los reportes de las tiendas alcanzan como respaldo ante ARCA y que no hay que guardar el detalle por usuario (CCyC art. 328, 10 años).

---

## 4. Pregunta 2: Términos y Privacidad

**Estado:** la app usa `https://portfolioai.app/terms` y `https://portfolioai.app/privacy` (`settings_screen.dart:425,431`, `auth_terms_disclaimer.dart:11-12`; la spec las centraliza en `lib/config/legal/legal_links.dart`). **No pude abrirlas:** el dominio no resuelve desde esta sesión porque está fuera de la red permitida. No sé si existen ni qué cubren. Para verificarlas, hay que habilitar `portfolioai.app` en la configuración de red de la sesión, o que el usuario las abra. En el repo no hay borrador. Asumo que la cláusula de suscripciones falta, así que va abajo.

### 4.1 Cláusula para Términos: "Suscripciones y renovación automática"

**es-ES**

> **Suscripciones y renovación automática.** Porty ofrece un plan gratuito y planes pagos (Premium y Gold) con facturación mensual o anual. Antes de comprar ves el nombre del plan, su duración y su precio en tu moneda, con los impuestos que correspondan según la tienda. El pago lo procesa Apple (App Store) o Google (Google Play) y se cobra en tu cuenta de esa tienda al confirmar la compra.
>
> La suscripción se renueva automáticamente al final de cada período, por la misma duración, salvo que la canceles al menos 24 horas antes de que termine el período actual. Si el precio cambia, la tienda te avisa antes y, cuando sus reglas lo exigen, te pide que aceptes el precio nuevo.
>
> Podés cancelar cuando quieras desde los ajustes de tu cuenta de App Store o Google Play. La cancelación corre desde el final del período que ya pagaste, y hasta ese momento seguís teniendo acceso a tu plan. Borrar la app o tu cuenta de Porty no cancela la suscripción.
>
> Los reembolsos los gestionan Apple o Google según sus políticas. Porty no puede emitirlos directamente. Si en algún momento ofrecemos un período de prueba, la parte que no uses se pierde al comprar la suscripción.
>
> Nada de esto limita los derechos que te reconozca la ley de protección al consumidor de tu país.

**en-US**

> **Subscriptions and automatic renewal.** Porty offers a free plan and paid plans (Premium and Gold) billed monthly or annually. Before you buy, you see the plan's name, length, and price in your currency, including any taxes applied by the store. Payment is processed by Apple (App Store) or Google (Google Play) and charged to your store account at confirmation of purchase.
>
> Your subscription renews automatically at the end of each period for the same length unless you cancel at least 24 hours before the end of the current period. If the price changes, the store will notify you in advance and, where its rules require it, ask you to accept the new price.
>
> You can cancel anytime in your App Store or Google Play account settings. Cancellation takes effect at the end of the period you've already paid for, and you keep access to your plan until then. Deleting the app or your Porty account doesn't cancel your subscription.
>
> Refunds are handled by Apple or Google under their policies; Porty can't issue them directly. If we ever offer a free trial, any unused portion is forfeited when you purchase a subscription.
>
> Nothing in this section limits any rights you have under the consumer protection laws of your country.

Los Términos también tienen que decir (verificar cuando se puedan abrir) que Porty da información y no asesoramiento financiero, no ejecuta órdenes y que las conexiones con brókers son de solo lectura, además de nombrar a Porty y no a PortfolioAI.

### 4.2 Párrafo para Privacidad: datos de compra

**es-ES**

> **Compras y suscripciones.** Las compras las procesan Apple o Google. Porty no recibe tus datos de pago. Usamos RevenueCat para saber qué plan tenés. Guardamos el tipo de evento (compra, renovación, cancelación), el producto, el precio y la moneda, la tienda, las fechas y la pantalla de la app desde la que compraste, para darte acceso a tu plan y medir cómo funciona la app. Si borrás tu cuenta, borramos tu perfil en RevenueCat y esos registros quedan desvinculados de vos: solo los usamos de forma agregada para métricas de ingresos.

**en-US**

> **Purchases and subscriptions.** Purchases are processed by Apple or Google; Porty never receives your payment details. We use RevenueCat to know which plan you have. We store the event type (purchase, renewal, cancellation), product, price and currency, store, dates, and the in-app screen you purchased from, to give you access to your plan and to understand how the app performs. If you delete your account, we delete your RevenueCat profile and these records are unlinked from you; we only use them in aggregate for revenue metrics.

Revisión humana: **sí** para los dos textos antes de publicarlos.

---

## 5. Pendientes para el envío (usuario)

1. Implementar el borrado de cuenta (H1). Es un bloqueo.
2. Abrir las dos URLs y confirmar que existen, que dicen Porty y que tienen §4.1 y §4.2. Si no, publicarlas antes del envío.
3. En App Store Connect: cargar la Privacy Policy URL y poner el link al EULA estándar de Apple o los Términos en la descripción.
4. No configurar ofertas introductorias ni trials en los anuales en este release (la app no los muestra; spec §6).

---

## 6. Textos finales del borrado de cuenta (brief `docs/product/briefs/2026-11-02-borrado-de-cuenta.md`)

Lo pidió porty-product-owner. Los nombres de clave son una propuesta; los define porty-architect o flutter-dev. `settings_delete_account_unavailable` se borra.

| Clave | es-ES (final) | en-US (final) |
|---|---|---|
| `settings_delete_account_title` | ¿Eliminar tu cuenta? | Delete your account? |
| `settings_delete_account_message` | Se borran tu cartera, tus conexiones con brókers, tus metas, alertas y planes, y tu historial con Porty. No se puede deshacer. Tus cuentas en los brókers no se tocan: solo se desconectan de Porty. | Your portfolio, broker connections, goals, alerts, plans, and history with Porty will be deleted. This can't be undone. Your broker accounts aren't affected; they're only disconnected from Porty. |
| `settings_delete_account_subscription_warning` | Tenés una suscripción activa en {store}. Borrar tu cuenta no la cancela: cancelala desde {store} para que no se te cobre de nuevo. | You have an active subscription on {store}. Deleting your account doesn't cancel it: cancel it on {store} so you're not charged again. |
| `settings_delete_account_manage_subscription` | Gestionar suscripción en {store} | Manage subscription on {store} |
| `settings_delete_account` (botón de confirmar, ya existe) | Eliminar cuenta | Delete account |
| `settings_delete_account_error` | No pudimos eliminar tu cuenta y no se borró nada. Probá de nuevo en un rato. | We couldn't delete your account, and nothing was deleted. Try again in a bit. |
| `settings_delete_account_done` | Eliminamos tu cuenta. Si volvés con el mismo mail, empezás de cero. | Your account has been deleted. If you come back with the same email, you'll start fresh. |

Condiciones de uso:
1. **Cuándo mostrar el aviso de suscripción:** cada vez que RevenueCat devuelva un entitlement activo (`premium` o `gold`), aunque esté cancelado y le quede período. No hay que intentar adivinar si se va a renovar. Cuesta poco mostrarlo de más, y no mostrarlo puede terminar en un cobro después del borrado y una reseña de una estrella.
2. **`{store}` tiene que ser la tienda donde se compró** (`EntitlementInfo.store`), no la plataforma actual. Si compró en iPhone y borra desde Android, el aviso dice App Store. Si la tienda es `PROMOTIONAL` o desconocida, se omite el aviso. El link va a `https://apps.apple.com/account/subscriptions` o a `https://play.google.com/store/account/subscriptions`.
3. **El aviso va antes del botón de confirmar**, en la misma hoja y con texto de peso normal. No puede quedar escondido en un "más info". Apple pide avisar que la facturación sigue hasta que el usuario cancele: https://developer.apple.com/support/offering-account-deletion-in-your-app/
4. **"No se borró nada" solo es cierto si** la función no borra `auth.users` cuando falla un paso. Si desconectar los brókers anduvo pero RevenueCat falló, las conexiones ya no están. En ese caso hay que usar: "No pudimos terminar de eliminar tu cuenta. Probá de nuevo; si sigue fallando, escribinos a {email}." / "We couldn't finish deleting your account. Try again; if it keeps failing, email us at {email}." Si el arquitecto confirma que las conexiones se pueden volver a armar, va el texto de la tabla.
5. **Lista de lo que se borra:** tiene que coincidir con las tablas que tienen `cascade`. Si algo se conserva (por ejemplo `subscription_events` cuando pase a `set null`, o el contador agregado `account_deleted`), no puede figurar como borrado. Por eso el texto no dice "todos tus datos".
6. **Backups:** el plazo en que los datos borrados desaparecen de las copias de seguridad de Supabase va en la política de privacidad, no en la hoja. Hay que confirmarlo según el plan de Supabase. Revisión humana: sí.
