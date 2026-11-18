# Builds por entorno (develop / prod)

Un mismo Release de Xcode y el mismo bundle id (`com.portyassistant.app`) generan dos tipos de build. El entorno se elige **al buildear**, con `--dart-define-from-file`:

| Build | Archivo | Backend de Supabase | Se ve |
|---|---|---|---|
| TestFlight (pruebas) | `env/develop.json` | branch **develop** | pastilla **DEV** arriba a la derecha |
| App Store (producción) | `env/prod.json` | branch **main** | sin pastilla |

La app lee la config **solo** desde `AppEnv` (`lib/config/env/app_env.dart`). Si al build le falta `SUPABASE_URL` o `SUPABASE_ANON_KEY`, la app corta en el arranque con un error que lo dice. Ya no hay `.env` en `assets/` ni `flutter_dotenv`.

## 1. Armar los archivos de entorno (una vez)

```bash
cp env/develop.json.example env/develop.json
cp env/prod.json.example env/prod.json
```

Los dos están en `.gitignore`; solo se commitean los `.example`.

| Clave | Qué es | ¿Obligatoria? |
|---|---|---|
| `APP_ENV` | `develop` o `prod` | sí (los scripts la exigen) |
| `SUPABASE_URL` | URL del proyecto/branch | sí |
| `SUPABASE_ANON_KEY` | anon (publishable) key del proyecto/branch | sí |
| `REVENUECAT_APPLE_API_KEY` / `REVENUECAT_GOOGLE_API_KEY` | claves **públicas** del SDK (`appl_…` / `goog_…`), las mismas en los dos archivos | sí para compras |
| `OPENAI_MODEL` | modelo que pide la app; vacío = el default del código | no |
| `YAHOO_CACHE_TTL_MINUTES` | caché de cotizaciones (default 10) | no |
| `SUPABASE_FUNCTIONS_REGION` | región fija de las edge functions (p. ej. `us-east-1`); vacío = la que elija Supabase | no |

**Nunca** pongas la service role key, ni `sb_secret_…`, ni claves de OpenAI o Finnhub: todo lo de `env/*.json` termina dentro del binario. Los scripts cortan si detectan una service role key.

### Dónde sacar la URL y la anon key de cada branch

1. Supabase Dashboard → el proyecto de Porty.
2. En la barra de arriba, elegí la branch: **main** para `prod.json` y **develop** para `develop.json`. Cada branch tiene su propio project ref, URL y keys.
3. **Project Settings → API**:
   - **Project URL** → `SUPABASE_URL` (`https://<ref>.supabase.co`).
   - **Project API keys → `anon` `public`** (o la *publishable key*) → `SUPABASE_ANON_KEY`. **No** la `service_role` ni la secret.

Por CLI: `supabase branches get develop` devuelve el ref y las keys de la branch.

## 2. Buildear

```bash
scripts/build_testflight.sh   # → env/develop.json, IPA para TestFlight
scripts/build_prod.sh         # → env/prod.json, IPA para App Store
```

Cada script valida el archivo: que exista, que sea JSON, que estén URL, anon key y `APP_ENV` sin los valores de ejemplo, que `APP_ENV` coincida con el script y que la key no sea la service role. Después imprime contra qué entorno va y corre `flutter build ipa --release --dart-define-from-file=…`. Los argumentos extra pasan a `flutter`, por ejemplo:

```bash
scripts/build_testflight.sh --build-number=42
```

El `.ipa` queda en `build/ios/ipa/`.

> ⚠️ **Nunca hagas Product → Archive en Xcode "en frío".** Xcode reutiliza los `DART_DEFINES` que dejó la última corrida de Flutter en `ios/Flutter/Generated.xcconfig`. Si lo último que corriste fue `flutter run` contra develop, un Archive sube a la tienda un build apuntando a develop, o sin config, y entonces la app no arranca. La forma recomendada es con los scripts; si preferís Xcode, seguí la sección siguiente al pie de la letra.

### Alternativa: Archive desde Xcode

1. En la terminal, **justo antes** de archivar, preparás Xcode para el entorno:
   ```bash
   scripts/prepare_xcode.sh develop   # TestFlight
   scripts/prepare_xcode.sh prod      # App Store
   ```
   El script valida `env/<entorno>.json` igual que los de build y corre `flutter build ios --release --config-only --dart-define-from-file=…`. Eso no compila nada: solo reescribe `Generated.xcconfig`. Después lee lo que quedó escrito y termina con una línea del tipo `✓ Xcode listo: APP_ENV=develop  SUPABASE_URL=https://…`. Si `APP_ENV` no coincide, corta.
2. Abrí `ios/Runner.xcworkspace` (el workspace, no el `.xcodeproj`).
3. Arriba, elegí el scheme **Runner** y el destino **Any iOS Device (arm64)**.
4. Si cambiaste de entorno respecto del último Archive: **Product → Clean Build Folder** (⇧⌘K).
5. **Product → Archive**. Entre el paso 1 y este, no corras `flutter run` ni `flutter build`: pisarían el entorno.
6. Se abre el Organizer con el archivo nuevo. Tocá **Distribute App → App Store Connect → Upload** y aceptá las opciones por defecto (firma automática).
7. Antes de cambiar de entorno, repetí desde el paso 1 con el otro.

Para confirmar qué entorno tiene Xcode en cualquier momento:

```bash
grep '^DART_DEFINES=' ios/Flutter/Generated.xcconfig | cut -d= -f2- | tr ',' '\n' | while read -r d; do echo "$d" | base64 --decode; echo; done | grep -E '^(APP_ENV|SUPABASE_URL)='
```

Android: el flavor elige el applicationId y el archivo elige el backend:

```bash
flutter build appbundle --release --flavor production --dart-define-from-file=env/prod.json
```

En local: `flutter run --dart-define-from-file=env/develop.json`. En VS Code, las configuraciones de `.vscode/launch.json` ya lo pasan.

## 3. Subir a App Store Connect

Las dos opciones suben el `.ipa` de `build/ios/ipa/`:

- **Transporter** (app de Apple, Mac App Store): arrastrá el `.ipa` y tocá *Deliver*.
- **CLI**, con una API key de App Store Connect (Users and Access → Integrations → App Store Connect API):
  ```bash
  xcrun altool --upload-app --type ios -f build/ios/ipa/*.ipa \
    --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
  ```
  La `.p8` va en `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8`.

Después, en App Store Connect el build aparece en TestFlight a los pocos minutos, cuando termina el *processing*.

**Cuidado:** los builds de develop y de prod comparten bundle id, así que todos caen en la misma lista de builds. Antes de mandar uno a revisión:

- Usá un build number distinto en cada subida.
- Anotá en *What to Test* cuál es de develop.
- Antes de mandar a revisión, instalá el build desde TestFlight y confirmá que **no** muestra la pastilla DEV.

## 4. Antes del primer build de develop

Pendiente del lado de Supabase (no lo hace la app):

- Secretos de las edge functions en la branch develop (OpenAI, Finnhub, etc.): `supabase secrets set --project-ref <ref develop> …`.
- Webhook de RevenueCat: apunta a una sola URL. Las compras sandbox de TestFlight solo actualizan el plan en develop si hay un webhook configurado hacia `https://<ref develop>.supabase.co/functions/v1/revenuecat-webhook`.
- Auth: URL Configuration y proveedores (Google) con la URL de la branch (ver `ci-cd.md`).
