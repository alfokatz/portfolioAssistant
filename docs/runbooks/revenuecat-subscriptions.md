# Activar las suscripciones (RevenueCat)

La app ya tiene el paywall, la compra, "Restaurar compras" y el webhook que
actualiza `user_subscriptions`. Falta configurar las tiendas, RevenueCat y el
`.env` del build. Mientras falte la clave pública de RevenueCat en el build,
el paywall muestra "Las compras no están disponibles ahora".

Cómo encaja todo: la app hace `Purchases.logIn(<uid de Supabase>)`, así que
en RevenueCat cada cliente es el uid del usuario. Al comprar, RevenueCat
llama al webhook `revenuecat-webhook`, que consulta los entitlements del
cliente (incluidos los promocionales) y escribe el plan más alto vigente
(gold > premium) en `user_subscriptions`.

Identificadores (tienen que coincidir exacto, ver
`lib/features/subscription/config/subscription_catalog.dart`):

| | Premium mensual | Premium anual | Gold mensual | Gold anual |
|---|---|---|---|---|
| Producto App Store | `portfolio_premium_monthly` | `portfolio_premium_annual` | `portfolio_gold_monthly` | `portfolio_gold_annual` |
| Suscripción : plan base Google Play | `portfolio_premium:monthly` | `portfolio_premium:annual` | `portfolio_gold:monthly` | `portfolio_gold:annual` |
| Package RevenueCat (offering `default`) | `premium_monthly` | `premium_annual` | `gold_monthly` | `gold_annual` |
| Entitlement RevenueCat | `premium` | `premium` | `gold` | `gold` |

Bundle iOS y package Android de producción: `com.portyassistant.app`.

## 0. Decidir antes

- [ ] Precios mensual y anual de Premium y Gold (propuesta: anual = 10× el mensual, sin ofertas de entrada).
- [ ] Países donde se vende (ideal: todos los de la ficha).

## 1. App Store Connect

- [ ] **Business → Agreements**: firmar *Paid Apps* y completar banco e impuestos. Sin esto Apple no entrega productos, ni en sandbox.
- [ ] **Tu app → Monetization → Subscriptions**: crear un grupo "Porty". Dentro, ordenar los niveles: Gold arriba (nivel 1), Premium abajo (nivel 2). Así pasar de Premium a Gold es una mejora inmediata.
- [ ] Crear las 4 suscripciones con los IDs de la tabla. En cada una: duración (1 mes / 1 año), precio, nombre y descripción en es y en, y una captura del paywall para la revisión.
- [ ] **Users and Access → Integrations → In-App Purchase**: generar una clave (`.p8`), anotar Key ID e Issuer ID.
- [ ] **Tu app → App Information → App-Specific Shared Secret**: generarlo.
- [ ] **Users and Access → Sandbox → Test Accounts**: crear un usuario sandbox (mail nuevo, que no sea un Apple ID real).

## 2. Google Play Console

- [ ] **Settings → Payments profile**: crear el perfil de comerciante.
- [ ] Subir un build (AAB de `production`) a **Testing → Internal testing**. Google no deja crear suscripciones sin un build con la librería de compras.
- [ ] **Monetize → Products → Subscriptions**: crear `portfolio_premium` y `portfolio_gold`. En cada una, dos planes base: `monthly` (renovación mensual) y `annual` (anual), con precio y activados.
- [ ] Cuenta de servicio para RevenueCat: seguir la guía de RevenueCat "Google Play service account credentials" (Google Cloud → cuenta de servicio con JSON → invitarla en Play Console → Users and permissions con permisos financieros). Los permisos pueden tardar hasta 36 h.
- [ ] **Settings → License testing**: agregar tu mail para comprar sin cargo.

## 3. RevenueCat

- [ ] **Project settings → Apps**:
  - App Store: bundle `com.portyassistant.app`, la `.p8` + Key ID + Issuer ID, y el shared secret.
  - Play Store: package `com.portyassistant.app` y el JSON de la cuenta de servicio.
- [ ] **Product catalog → Products**: importar los 4 de Apple y los 4 de Google.
- [ ] **Entitlements**: crear `premium` y `gold` (nombres exactos). A cada uno, sus productos mensual y anual de las dos tiendas.
- [ ] **Offerings**: crear `default`, marcarlo **Current** y agregar los 4 packages con los identificadores de la tabla (custom identifier), cada uno con su producto de iOS y de Android.
- [ ] **Integrations → Webhooks**:
  - URL: `https://rungwxgkwxtekijbynkm.supabase.co/functions/v1/revenuecat-webhook`
  - Authorization header: `Bearer <REVENUECAT_WEBHOOK_SECRET>` (el mismo valor cargado en Supabase).
  - Environment: Production y Sandbox (para probar).
- [ ] **API keys**: copiar las públicas, `appl_…` y `goog_…`. La `sk_…` nunca va en la app (ya está en Supabase como `REVENUECAT_SECRET_API_KEY`).
- [ ] **Customers → tu usuario (uid de Supabase) → Grant promotional entitlement → `gold`, Lifetime**: así una restauración o una compra de prueba no te baja a Free.

## 4. Supabase

- [ ] `npx supabase secrets list`: tienen que estar `REVENUECAT_WEBHOOK_SECRET` y `REVENUECAT_SECRET_API_KEY` (v1, `sk_`).
- [ ] `revenuecat-webhook` desplegada (ya lo está si corriste `npx supabase functions deploy`).

## 5. Build

En `assets/env/.env.production` (local, no va al repo; si probás con otro flavor, en ese `.env`):

```
REVENUECAT_APPLE_API_KEY=appl_...
REVENUECAT_GOOGLE_API_KEY=goog_...
```

Compilar siempre con el flavor: `flutter run --dart-define=FLAVOR=production` (iOS) o `--flavor production` (Android).

## 6. Probar

- [ ] iPhone: Ajustes → App Store → Cuenta de sandbox → entrar con el usuario sandbox. Instalar desde Xcode o TestFlight.
- [ ] Android: instalar desde el link de prueba interna con el mail de tester.
- [ ] Con una cuenta Free de prueba (no la tuya):
  - [ ] El paywall muestra precio y período reales de la tienda (no "Precio al confirmar la compra").
  - [ ] Comprar Premium mensual: se cierra el paywall y la app pasa a Premium.
  - [ ] En Supabase, `user_subscriptions` de ese usuario: `tier = premium`, `status = active`, `provider` de RevenueCat.
  - [ ] Pasar de Premium a Gold: queda `gold`.
  - [ ] Cancelar en la tienda (sandbox renueva cada pocos minutos): al vencer vuelve a `free`.
  - [ ] Reinstalar y "Restaurar compras": vuelve el plan.
- [ ] RevenueCat → Integrations → Webhooks: los eventos figuran con respuesta 200. Si dan 401, el header no coincide con `REVENUECAT_WEBHOOK_SECRET`.

## 7. Antes de enviar a revisión

- [ ] `porty-compliance` revisa el paywall con precios reales: precio, período, renovación automática y cómo cancelar visibles antes de comprar; links a Términos y Privacidad.
- [ ] App Store Connect: adjuntar las 4 suscripciones a la versión que se envía (se revisan con la app).
- [ ] Nota para el revisor de Apple: cuenta demo y dónde está el paywall.
