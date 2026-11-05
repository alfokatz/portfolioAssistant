# CI/CD

## CI (`.github/workflows/ci.yml`)

Corre en cada PR y en cada push a `main` o a ramas `claude/**`. No necesita configuración.

| Job | Qué verifica |
|---|---|
| Flutter | `flutter analyze` sin errores (warnings e infos no frenan) y la suite completa de `flutter test` (screenshots y evals pagas se saltean solas) |
| Supabase | `supabase start` aplica todas las migraciones desde cero (si una migración no corre, falla acá), tests de Deno de las edge functions y los tests SQL de `supabase/tests/` |

Si el CI falla en un PR, no se mergea. Para ver el error: GitHub → Actions → la corrida → el paso en rojo.

## Deploy de Supabase (`.github/workflows/deploy-supabase.yml`)

Al mergear a `main` cambios en `supabase/` (o a mano con "Run workflow"): vista previa de migraciones, `db push` y deploy de todas las edge functions. **Espera tu aprobación** antes de tocar producción.

### Configuración (una sola vez)

1. GitHub → repo → **Settings → Environments → New environment** → `production`.
   - **Required reviewers**: tu usuario. Sin esto el deploy corre sin pedir permiso.
   - (Opcional) **Deployment branches**: solo `main`.
2. En ese environment, **Environment secrets**:
   - `SUPABASE_ACCESS_TOKEN`: Supabase → Account → Access Tokens → generar.
   - `SUPABASE_DB_PASSWORD`: la contraseña de la base (Project Settings → Database).
   - `SUPABASE_PROJECT_REF`: el id del proyecto (lo que va en `https://<ref>.supabase.co`).
3. Los secretos de las edge functions (OpenAI, RevenueCat, SnapTrade, eToro, Finnhub…) **no** van acá: siguen en Supabase (`supabase secrets set`).

### Cómo se usa

1. Se mergea un PR a `main` con cambios en `supabase/`.
2. GitHub te avisa que el deploy espera aprobación → **Review deployments → Approve**.
3. El paso "Migraciones pendientes (vista previa)" muestra qué se va a aplicar antes de aplicarlo.

Antes del primer deploy con el borrado de cuenta, correr la consulta de solo lectura de `docs/runbooks/account-deletion.md`.
