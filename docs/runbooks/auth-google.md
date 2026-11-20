# Login y registro: Google OAuth y seguridad

Cómo queda armado el login y qué hay que configurar fuera del repo para que
funcione en un dispositivo.

## Cómo funciona

| Flujo | Qué pasa | Deep link |
|---|---|---|
| Google | `getOAuthSignInUrl` (PKCE) → navegador del sistema (`flutter_web_auth_2`: ASWebAuthenticationSession / Auth Tab) → Supabase vuelve con `code` → `exchangeCodeForSession` | `porty-oauth://callback` |
| Registro con email | `signUp` → email de confirmación → el link abre la app y supabase_flutter canjea el `code` | `porty://login-callback` |
| Olvidé mi contraseña | `resetPasswordForEmail` → el link abre la app → evento `passwordRecovery` → el router fuerza `/reset-password` hasta guardar una nueva o cerrar sesión | `porty://reset-password` |

Código: `lib/config/supabase/supabase_auth_service.dart`,
`lib/config/supabase/supabase_redirect_url.dart`,
`lib/presentation/flows/auth/`.

El esquema de OAuth (`porty-oauth`) solo lo registra el `CallbackActivity`
de `flutter_web_auth_2` en Android (en iOS lo captura la sesión de
autenticación). El de los emails (`porty`) está en `Info.plist` y en el
intent-filter de `MainActivity`. El deep linking de Flutter está apagado en
las dos plataformas: esos links los procesa supabase_flutter, no GoRouter.

## Medidas de seguridad

- **PKCE** en todos los flujos: un `code` interceptado no sirve sin el
  verifier, que no sale del dispositivo.
- **Sesión en Keychain / Keystore** (`SecureSessionStorage`), no en
  SharedPreferences. Migra la sesión de versiones anteriores sin desloguear y,
  en una instalación nueva, borra sesiones que hayan quedado en el Keychain.
- **Política de contraseñas** (registro y reset): 8+ caracteres, mayúscula,
  minúscula y número, máximo 72 bytes (límite de bcrypt). Igual en la app
  (`AuthValidators`) y en Supabase.
- **Sin enumeración de cuentas**: el registro muestra "Revisá tu email" exista
  o no la cuenta; el reset responde siempre lo mismo.
- **Errores traducidos**: nunca se muestra el mensaje crudo del servidor
  (`AuthFailure`).
- **Freno a la fuerza bruta**: tras 5 contraseñas incorrectas el login se
  bloquea 30 s, duplicándose hasta 15 min. El límite real es el rate limit de
  Supabase por IP.
- **Espera de 60 s** para reenviar emails de confirmación o de reset.
- **Al cambiar la contraseña** se cierran las demás sesiones.

## Configuración (una vez por entorno)

### 1. Google Cloud Console

1. APIs & Services → OAuth consent screen: nombre **Porty**, logo, email de
   soporte, links de privacidad y términos. Scopes: `openid`, `email`,
   `profile` (no hace falta ninguno sensible).
2. Credentials → Create credentials → OAuth client ID → tipo **Web
   application** (es el que usa Supabase, aun desde el celular).
   - Authorized redirect URIs: `https://<project-ref>.supabase.co/auth/v1/callback`
     (y `http://127.0.0.1:54321/auth/v1/callback` para el Supabase local).
3. Anotar el **Client ID** y el **Client secret**.

No hacen falta clients de Android/iOS ni SHA-1: el login pasa por el
navegador del sistema, no por el SDK nativo de Google.

### 2. Supabase (proyecto hosteado)

Dashboard → Authentication:

- **Providers → Google**: Enable, pegar Client ID y Client secret.
- **URL Configuration → Redirect URLs**: agregar
  - `porty-oauth://callback`
  - `porty://login-callback`
  - `porty://reset-password`
- **Providers → Email**: *Confirm email* activado, *Secure password change*
  activado.
- **Policies / Passwords**: largo mínimo 8 y "Lowercase, uppercase letters and
  digits". (Opcional, plan Pro: *Prevent use of leaked passwords*.)
- **Rate limits**: dejar los de fábrica o más estrictos.
- **Email templates**: los links usan `{{ .ConfirmationURL }}`, que ya respeta
  el `redirect_to` que manda la app.

### 3. Supabase local

`supabase/config.toml` ya trae todo lo anterior. Las credenciales de Google
van en `supabase/.env` (no se commitea):

```
SUPABASE_AUTH_EXTERNAL_GOOGLE_CLIENT_ID=...
SUPABASE_AUTH_EXTERNAL_GOOGLE_SECRET=...
```

## Probar en un dispositivo

1. Iniciar sesión con Google: elige la cuenta en la hoja del sistema y vuelve
   a la app logueado. Cerrar la hoja no muestra ningún error.
2. Registrarse con email → "Revisá tu email" → abrir el link **en el mismo
   teléfono** → entra a la app (onboarding).
3. "¿Olvidaste tu contraseña?" → abrir el link → pantalla "Nueva contraseña"
   → guardar → entra a la app. Las otras sesiones se cierran.
4. 5 contraseñas incorrectas seguidas → botón bloqueado con cuenta regresiva.

Si el link de un email se abre en otro dispositivo, el email igual queda
confirmado pero el `code` no se puede canjear (falta el verifier): la app
muestra "El link venció o ya se usó…" y el usuario inicia sesión normal.

## Screenshots

```
RUN_SCREENSHOTS=1 SCREENSHOTS_OUT=/tmp/shots \
  flutter test test/screenshots/auth_screenshots_test.dart
```
