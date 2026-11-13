# Porty: checklist fuera del código

Cambios a mano que acompañan el renombre de la app a **Porty** y el login nuevo. En el código ya está todo hecho (ver el final). Nada de esto se cambió desde el repo.

## Nombre en las tiendas

| Campo | Valor | Largo |
|---|---|---|
| Nombre (App Store y Google Play) | Porty: asistente de portfolio | 29 / 30 |
| Subtítulo App Store / descripción corta Play | Tu asistente de inversiones | 27 (App Store 30, Play 80) |

## Antes que nada: identificadores

- [x] **Bundle id de iOS.** 2026-11-05: `com.portyassistant.app` (igual que Android), registrado en Apple Developer con Push Notifications y Sign in with Apple, y app creada en App Store Connect. Reemplaza a `app.portfolioai.porty` (nunca se registró) y a `uy.gub.bps.movil.bpsfuncionarios` (venía de otro proyecto).
- [ ] **Push en iOS desactivado temporalmente.** El 2026-10-21 se sacó `aps-environment` de `ios/Runner/Runner.entitlements` para poder firmar con el Personal Team (gratis, no soporta push). Cuando esté la cuenta paga del Apple Developer Program: elegir ese team en Xcode y volver a agregar `<key>aps-environment</key><string>development</string>` (o la capability Push Notifications desde Signing & Capabilities).
- [x] **Esquemas de deep link de auth.** Ya registrados en iOS y Android (`porty-oauth://callback`, `porty://login-callback`, `porty://reset-password`). Falta agregarlos en Supabase → Auth → URL Configuration → Redirect URLs: ver `docs/runbooks/auth-google.md`.

## Google Cloud Console

- [ ] APIs & Services → OAuth consent screen (Branding): **App name** = `Porty`, logo de Porty, email de soporte, links de privacidad y términos.
- [ ] Si la pantalla de consentimiento está publicada ("In production"), cambiar el nombre o el logo puede pedir una nueva verificación de Google.
- [ ] Credentials: los nombres de los OAuth clients son internos. Opcionalmente, renombralos para ordenarte.

## Supabase (Dashboard → Authentication)

- [ ] **Email templates**: cambiar "PortfolioAI" / "PortfolioAssistant" por Porty en el asunto y el cuerpo de:
  - Confirm signup
  - Reset password
  - Magic link
  - Invite user
  - Change email address
  - Reauthentication
- [ ] **SMTP Settings** (si usás SMTP propio): *Sender name* = `Porty`.
- [ ] **URL Configuration**: Site URL y Redirect URLs (ver deep link más arriba).
- [ ] `supabase/config.toml` tiene `project_id = "portfolio_assistant"`. Es técnico y no lo ve el usuario: no hace falta cambiarlo.

## Sign in with Apple (flujo nativo, activo desde el 2026-11-13)

La app ofrece Apple arriba de Google, solo en iOS (guía 4.8 de la App Store).

**Apple Developer**
- [x] App ID `com.portyassistant.app` con **Sign In with Apple**.
- [x] Key con Sign in with Apple (`.p8`, Key ID, Team ID), guardada en el gestor de contraseñas.
- No hace falta Services ID: el login es nativo (sin flujo web).

**Supabase → Authentication → Providers → Apple (producción y develop)**
- [x] Enable, Client IDs = `com.portyassistant.app`. Secret Key (for OAuth) vacío: solo lo usa el flujo web, así no hay que renovarlo cada 6 meses.

**Secretos de edge functions (producción y develop), para revocar al borrar la cuenta**
- [x] `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_CLIENT_ID` (bundle id), `APPLE_PRIVATE_KEY` (contenido del `.p8`).

**Código**
- [x] Hoja nativa con `sign_in_with_apple`: nonce SHA-256 + `signInWithIdToken` (`SupabaseAuthService.signInWithApple`). El nombre, que Apple manda solo la primera vez, se guarda en `user_metadata`.
- [x] Logo oficial de la manzana en `AppleSignInButton` (`AppleLogoPainter`).
- [x] Capability `com.apple.developer.applesignin` en `Runner.entitlements`.
- [x] `APPLE_SIGN_IN_ENABLED` prendido por defecto; `--dart-define=APPLE_SIGN_IN_ENABLED=false` lo apaga.
- [x] Borrar cuenta (5.1.1(v)): la app pide a Apple un código y `delete-account` lo canjea y revoca el token (`delete-account/apple.ts`, best effort). Si el usuario cierra la hoja de Apple, no se borra nada.
- [ ] Probar en un iPhone real: login con Apple (incluido "Ocultar mi email"), cerrar sesión y volver a entrar, y borrar la cuenta (en Ajustes del iPhone → Apple ID → Iniciar sesión con Apple, Porty tiene que desaparecer).

## App Store Connect

- [ ] App Information: **Name** `Porty: asistente de portfolio`, **Subtitle** `Tu asistente de inversiones`.
- [ ] Versión: descripción, keywords, texto promocional, screenshots nuevos (el login cambió) y "What's New".
- [ ] Privacy Policy URL, Support URL y Marketing URL (ver dominio más abajo).
- [ ] In-App Purchases / Subscriptions: **display name y descripción** de cada producto (`portfolio_premium_monthly`, etc.) y la **localización del grupo de suscripción** (es el nombre que se ve en Ajustes → Suscripciones del iPhone). El product id es técnico: no se cambia.
- [ ] App Review Information: notas para el revisor y cuenta demo.

## Google Play Console

- [ ] Store presence → Main store listing: **App name**, **Short description** (`Tu asistente de inversiones`), Full description, feature graphic y screenshots.
- [ ] Monetize → Products / Subscriptions: nombre y descripción visibles de cada producto (no el id).
- [ ] Opcional: App content → Data safety, si el texto menciona el nombre.

## RevenueCat

- [ ] Project settings: nombre del proyecto y de las apps (iOS / Android). Es interno, pero aparece en emails y en el dashboard.
- [ ] Paywalls (si usás paywalls de RevenueCat): títulos y textos que digan PortfolioAI. El paywall de la app es propio (`subscription_paywall_sheet.dart`, textos en las traducciones, ya revisados), así que esto aplica solo si hay paywalls remotos configurados.
- [ ] Offerings / Packages: el display name y la metadata de cada offering, si se muestran.
- [ ] Customer emails / notificaciones: el remitente y la marca.

## Dominio y links legales

- [ ] Términos, Privacidad y "Calificar" apuntan a `https://portfolioai.app/terms`, `/privacy` y `/rate` (`auth_terms_disclaimer.dart`, `settings_screen.dart`). El dominio no lo cambié: decidí si queda, si redirige a uno nuevo o si se cambia en el código. Además, el **contenido** de esas páginas probablemente dice PortfolioAI.

## Ícono y assets

- [ ] El ícono de la app (`flutter_launcher_icons`) no se tocó. Si todavía es el sparkle charcoal, considerá alinearlo con el avatar terracota de Porty que ahora encabeza el login.
- [ ] Launch screen (`LaunchScreen.storyboard`): revisar que no tenga el nombre viejo como imagen.

## Lo que ya quedó hecho en el código

- Nombre visible: iOS `CFBundleDisplayName` y `CFBundleName` = Porty; Android `android:label` = Porty; web (`manifest.json`, `<title>`); títulos de ventana en Windows y Linux.
- Textos en `assets/translations/{es-ES,en-US}.json` y en DESIGN.md, PRODUCT.md y README.
- No se cambiaron: bundle id, applicationId/namespace, el paquete Dart `portfolio_assistant`, los nombres de clases ni el `PRODUCT_NAME` de macOS (es el nombre del binario).
- `test/branding/no_old_app_name_test.dart` falla si vuelve a aparecer el nombre viejo en un texto visible.
