# CI/CD

## CI (`.github/workflows/ci.yml`)

Corre en cada PR y en cada push a `main`, `develop` o a ramas `claude/**`. No necesita configuración.

| Job | Qué verifica |
|---|---|
| Qué cambió | Mira qué carpetas tocó el cambio. En PRs y ramas de trabajo se saltea lo que no aplica: sin cambios de app (`lib/`, `test/`, `assets/`, `pubspec`, `android/`, `ios/`, `web/`, las allowlists de `ai-chat`) no corre Flutter; sin cambios en `supabase/` no corre Supabase. Push a `main`/`develop` y "Run workflow" corren todo |
| Flutter analyze | `flutter analyze` sin errores (warnings e infos no frenan) |
| Flutter tests (shard 1-4/4) | La suite completa de `flutter test`, partida en 4 máquinas en paralelo (`--total-shards 4`). Screenshots y evals pagas se saltean solas. Si un shard falla, los otros siguen: se ven todas las fallas juntas |
| Supabase | `supabase start` aplica todas las migraciones desde cero (si una migración no corre, falla acá), tests de Deno de las edge functions y los tests SQL de `supabase/tests/` |
| Controles (observe) | Solo en PRs. Corre `tools/verify/check-controls.sh` **tomado de la rama base**: avisa si el PR mezcla controles (`REVIEW.md`, `CLAUDE.md`, hooks, CI, `test/security/`, `tools/verify/`) con código, y qué commits no tienen línea `Verified:`. Hoy solo avisa; para que bloquee, `CONTROLS_GATE: enforce` en el job |
| E2E web (observe) | Solo en PRs con cambios de app. Compila la app para web contra Supabase local y corre los flujos de `tools/verify/e2e/flows.mjs` con Playwright. Sube las capturas como artefacto `e2e-capturas`. Tiene `continue-on-error`: todavía no bloquea el merge |
| CI ok | Resume todo en un check: falla si algún job falló o se canceló (los salteados cuentan como ok). Es el que conviene marcar como requerido en la protección de ramas |

Para reproducir un shard en local: `flutter test --total-shards 4 --shard-index 0` (índices 0 a 3). Si un shard queda mucho más lento que los otros o la suite crece, subir a 6 shards en `matrix.shard` y `--total-shards`.

Si el CI falla en un PR, no se mergea. Para ver el error: GitHub → Actions → la corrida → el paso en rojo.

### Compuertas de verificación: de observe a enforce

Las tres compuertas arrancan en **observe** (anotan, no bloquean), para ver falsos positivos antes de frenar a nadie:

| Compuerta | Dónde se cambia | Pasar a enforce cuando… |
|---|---|---|
| Hook Stop de Claude (`porty-verify-gate`) | `PORTY_VERIFY_GATE` en `.claude/settings.json` | `.claude/verify-gate.log` muestra pocos falsos positivos durante 2 semanas |
| Controles en CI | `CONTROLS_GATE` en el job `controles` | los PRs nuevos ya salen separados y con `Verified:` |
| E2E en CI | sacar `continue-on-error` del job `e2e` y sumarlo a `needs` de `CI ok` | 2-3 semanas sin fallas que no sean bugs reales |

Una vez al mes: `tools/verify/stats.sh "30 days ago"` (commits verificados, reverts, fixes que podrían volverse reglas de `REVIEW.md`).

## Ramas y entornos

| Rama git | Supabase | Deploy |
|---|---|---|
| `develop` | rama persistente `develop` (Branching, plan Pro) | `deploy-supabase-develop.yml`, automático al pushear cambios en `supabase/`: migraciones + edge functions |
| cualquier otra (menos `main`) | la misma rama `develop` de Supabase | `deploy-supabase-develop.yml`: **solo edge functions** (las migraciones, vista previa sin aplicar) |
| `main` | producción | `deploy-supabase.yml`, con tu aprobación |

Flujo: rama de trabajo → PR a `develop` → se despliega a Supabase develop y probás la app con el flavor `development` → PR de `develop` a `main` → aprobás el deploy a producción. Nunca se cambia el esquema a mano en ninguno de los dos: todo va por migraciones.

## Deploy de Supabase develop (`.github/workflows/deploy-supabase-develop.yml`)

Igual que el de producción, pero contra la rama `develop` de Supabase y sin aprobación. Corre con cualquier push con cambios en `supabase/` a una rama que no sea `main`: despliega las edge functions de esa rama (para probar, por ejemplo, el chat antes de mergear; el último push gana) y aplica migraciones solo si la rama es `develop`. Si el environment `development` tiene "Deployment branches" limitado a `develop`, ampliarlo a todas las ramas (o "No restriction") para que corra desde las ramas de trabajo.

### Configuración (una sola vez)

1. Supabase → proyecto → **Branches** → crear la rama `develop` y marcarla **persistente** (sin integración con GitHub: el deploy lo hace este workflow). Por CLI: `supabase branches create develop --persistent`.
2. Datos de la rama: `supabase branches get develop` (o el dashboard con la rama elegida) → `project ref` y contraseña de la base.
3. GitHub → **Settings → Environments → New environment** → `development` (sin reviewers). **Environment secrets**:
   - `SUPABASE_ACCESS_TOKEN`: el mismo token de Supabase que producción.
   - `SUPABASE_DEV_PROJECT_REF`: el `project ref` de la rama develop.
   - `SUPABASE_DEV_DB_PASSWORD`: la contraseña de la base de la rama.
4. Primer deploy: GitHub → Actions → **Deploy Supabase (develop)** → **Run workflow** (rama `develop`).
5. Lo que no se copia de producción y hay que cargar en la rama: secretos de las edge functions (`supabase secrets set --project-ref <ref develop> --env-file ...`, con claves de sandbox donde haya), `project_url` y `cron_secret` en el Vault (ver `push-notifications.md`; sin `project_url` los cron no llaman a nada), URL Configuration y proveedores de Auth (Google/Apple) con la URL de la rama.
6. App: `assets/env/.env.development` con la `SUPABASE_URL` y `SUPABASE_ANON_KEY` de la rama.

## Deploy de Supabase producción (`.github/workflows/deploy-supabase.yml`)

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
