# Porty: checklist fuera del código

Cambios a mano que acompañan el renombre de la app a **Porty** y el login nuevo. En el código ya está todo hecho (ver el final). Nada de esto se cambió desde el repo.

## Nombre en las tiendas

| Campo | Valor | Largo |
|---|---|---|
| Nombre (App Store y Google Play) | Porty: asistente de portfolio | 29 / 30 |
| Subtítulo App Store / descripción corta Play | Tu asistente de inversiones | 27 (App Store 30, Play 80) |

## Antes que nada: identificadores

- [ ] **Bundle id de iOS.** Hoy es `uy.gub.bps.movil.bpsfuncionarios`, que parece copiado de otro proyecto. No lo cambié porque cambiarlo equivale a publicar otra app. Si la app todavía no está publicada con ese id, conviene registrar uno propio en Apple Developer **antes** de configurar Sign in with Apple, RevenueCat y los productos de App Store, porque todo eso queda atado al bundle id. Si ya está publicada, se queda como está.
- [ ] **Esquema de deep link de OAuth.** El callback es `com.example.portfolioassistant://login-callback`, pero ni `ios/Runner/Info.plist` (no tiene `CFBundleURLTypes`) ni `AndroidManifest.xml` (no tiene un intent-filter con ese `scheme`) lo registran. Sin eso, en un dispositivo la vuelta del login con Google no abre la app. Hay que registrarlo en las dos plataformas y en Supabase → Auth → URL Configuration → Redirect URLs. El esquema es técnico y no lo ve el usuario, así que puede seguir siendo este o pasar a uno propio.

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

## Sign in with Apple (hoy NO está activo)

Hoy la app ofrece Google y no ofrece Apple. Con eso, la guía **4.8** de la App Store puede rechazar la app en revisión. El servicio ya tiene `signInWithApple()` (flujo web vía Supabase), pero no había botón, entitlement ni configuración. El botón ya está en el diseño, apagado detrás de `--dart-define=APPLE_SIGN_IN_ENABLED=true` y visible solo en iOS.

**Apple Developer (Certificates, Identifiers & Profiles)**
- [ ] Identifiers → el App ID de la app → habilitar la capability **Sign In with Apple**.
- [ ] Keys → crear una key con **Sign in with Apple** habilitado. Bajar el `.p8` y anotar el Key ID y el Team ID.
- [ ] Solo para el flujo web/OAuth (o para Android y web): Identifiers → **Services ID** (ej. `<bundle-id>.signin`). Configurarle el dominio `<project-ref>.supabase.co` y la Return URL `https://<project-ref>.supabase.co/auth/v1/callback`.

**Xcode**
- [ ] Runner → Signing & Capabilities → **+ Sign In with Apple**. Esto crea `Runner.entitlements` con `com.apple.developer.applesignin`.

**Supabase → Authentication → Providers → Apple**
- [ ] Enable.
- [ ] Client IDs: el bundle id (flujo nativo) y el Services ID (flujo web).
- [ ] Secret key: el JWT generado con el `.p8`, el Key ID y el Team ID (lo necesita el flujo OAuth). **Vence cada 6 meses**: agendá la renovación.

**Código, cuando esté lo anterior (recomendado)**
- [ ] Pasar al flujo nativo: hoy `signInWithApple()` abre Safari, y Apple espera la hoja nativa. Se hace con `sign_in_with_apple` + nonce SHA-256 + `supabase.auth.signInWithIdToken(provider: OAuthProvider.apple, idToken: …, nonce: …)`. Apple manda el nombre solo en el primer login: guardarlo en `user_metadata`.
- [ ] El logo del botón hoy es `Icons.apple` de Material. Para la revisión, usar el logo oficial de Apple Design Resources o el botón del sistema (`SignInWithAppleButton`). El tamaño, el radio y la posición ya están resueltos en `AppleSignInButton`.
- [ ] Buildear con `--dart-define=APPLE_SIGN_IN_ENABLED=true`.
- [ ] La app ya tiene "Eliminar cuenta" en Settings (lo exige la 5.1.1(v) con login social). Con Apple, al borrar la cuenta también hay que revocar el token (`/auth/revoke`).

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
