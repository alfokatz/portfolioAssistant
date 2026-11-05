# Spec: hábito del sábado (3 informes completos de regalo)

**Fecha:** 2026-11-03 · **Autor:** porty-architect · **Estado:** lista para construir
**Implementa:** apuesta "Hábito del sábado" de `docs/product/roadmap.md` (en el roadmap es la #5; el usuario la aprobó como "apuesta 4"). Insumo: `docs/growth/2026-11-02-palancas-a-pago.md` E3. La push del sábado (E4) ya existe (`daily-jobs` → `weeklyReportRows`) y no se toca: la configuración de Firebase/APNs es del usuario (`docs/runbooks/push-notifications.md`).
**Comparte con:** `2026-11-03-free-prueba-premium.md` la migración `20261103110000_rollout_flag_sql.sql` (mismo dueño, se crea una vez).

---

## 1. Objetivo

Hoy Free y Premium reciben **un** informe semanal completo (con Porty) y desde el siguiente ven solo números + teaser de Gold: pierden el informe antes de extrañarlo. Con el interruptor prendido, reciben los **primeros N informes completos** (N en `app_config`, por defecto 3) y el copy dice cuál es ("Informe de regalo 2 de 3", "el último").

**Listo** = criterios de §5 en verde; con el interruptor apagado el comportamiento es idéntico al de hoy (N = 1).

## 2. Fuera de alcance

- La push del sábado, sus textos y la configuración de Firebase/APNs (F0, del usuario).
- Cambiar el contenido del informe, su prompt o el teaser de Gold (`weekly_report_locked_*`).
- Contar por "semanas desde el alta" (ver §6).
- Gold (siempre completo, sin cambios).
- Eventos nuevos: se mide con `weekly_report_opened` y `paywall_viewed{source: weekly_report}` que ya existen, más `weekly_reports.courtesy`.

---

## 3. Contrato de datos

### 3.1 Helper SQL de interruptores (compartido)

`supabase/migrations/20261103110000_rollout_flag_sql.sql` (backend). Evalúa en el servidor una fila con formato `PortyRolloutFlag` (`{"percent","users"}`) **igual que la app y que `rolloutBucket` de `ai-chat`** (FNV-1a de 32 bits sobre el id en texto, `% 100`):

```sql
-- true si [p_user_id] está en `users` o su bucket < percent. Falla cerrado
-- (sin fila, valor raro o p_user_id null → false).
create or replace function public._rollout_on(p_key text, p_user_id uuid)
returns boolean language plpgsql stable security definer set search_path = public;

-- 0..99, mismo resultado que PortyRolloutFlag.bucket / rolloutBucket.
create or replace function public._rollout_bucket(p_user_id uuid)
returns int language plpgsql immutable;
```

Implementación: `h bigint := 2166136261`; por cada carácter de `p_user_id::text`: `h := h # ascii(c); h := (h * 16777619) % 4294967296;` → `h % 100`. Revocar ambos de `public, anon, authenticated`.

Vectores de prueba (calculados con el algoritmo de la app):

| user_id | bucket |
|---|---|
| `00000000-0000-0000-0000-0000000000d1` | 70 |
| `00000000-0000-0000-0000-0000000000d2` | 51 |
| `00000000-0000-0000-0000-0000000000a1` | 3 |
| `00000000-0000-0000-0000-0000000000a2` | 22 |

### 3.2 Interruptor y N

`supabase/migrations/20261103120000_weekly_report_courtesy.sql` (backend):

```sql
insert into public.app_config (key, value)
values ('weekly_report_courtesy', '{"percent": 0, "users": [], "reports": 3}'::jsonb)
on conflict (key) do nothing;

-- Informes completos de regalo para [p_user_id]: 1 con el interruptor
-- apagado (lo de hoy); con el interruptor, `reports` acotado a 1..8
-- (3 si falta o no es número).
create or replace function public._weekly_courtesy_limit(p_user_id uuid)
returns int language sql stable security definer set search_path = public;
```

Prender (lo hace el usuario): `update public.app_config set value = '{"percent": 100, "users": [], "reports": 3}'::jsonb, updated_at = now() where key = 'weekly_report_courtesy';`. Cambiar N = cambiar `reports`, sin publicar.

Clave aparte de `weekly_report` (`{"enabled"}`) a propósito: el runbook la actualiza con `set value = '{"enabled": true}'`, que borraría N.

### 3.3 `claim_weekly_report` (redefinida en la misma migración)

Copiar el cuerpo **vigente** (`20261002130000_weekly_report_flag.sql`, con el estado `disabled`) y cambiar solo esto:

1. Fila nueva de alguien sin Gold: en vez de `exists (... courtesy)` → `numbers_only`, contar `count(*) where user_id = v_user_id and courtesy` (cualquier `status`, como hoy) y devolver `numbers_only` si `>= _weekly_courtesy_limit(v_user_id)`.
2. Las respuestas `claimed` con `courtesy = true` suman dos campos:

```jsonc
// fila nueva, tercer regalo de 3
{"state": "claimed", "courtesy": true, "attempt": 1, "courtesy_number": 3, "courtesy_total": 3}
// re-claim de una fila existente (intento 2): number = regalos con week_start <= esta semana
{"state": "claimed", "courtesy": true, "attempt": 2, "courtesy_number": 2, "courtesy_total": 3}
// Gold: sin los campos
{"state": "claimed", "courtesy": false, "attempt": 1}
```

`courtesy_total` = `_weekly_courtesy_limit` en ese momento. `ready`, `in_progress`, `numbers_only`, `failed`, `disabled` no cambian: en `ready` los números viajan dentro del `payload` (los guarda la app, §3.4). Permisos y `grant`s, iguales que hoy. `gold_data_allowed` y `ai_report_begin` no cambian (el regalo ya habilita los datos de Gold mientras se genera).

### 3.4 App

- `WeeklyReportClaim.parse`: `ClaimGranted` suma `final int? courtesyNumber; final int? courtesyTotal;` (null si faltan o no son enteros ≥ 1).
- `WeeklyReport` suma los mismos dos campos, en `toJson` (`courtesy_number`, `courtesy_total`) y en `tryParse` (opcionales: un payload viejo sin ellos sigue siendo válido; `schemaVersion` sigue en 2).
- El controller los pasa de `ClaimGranted` a `WeeklyReport.compose` (también en la variante `numbersUnavailable` de una generación fallida).
- Pantalla (`weekly_report_screen.dart`, donde hoy está `weekly_report_courtesy`):
  - `courtesyTotal == null || courtesyTotal <= 1` → `weekly_report_courtesy` (texto de hoy).
  - `courtesyNumber < courtesyTotal` → `weekly_report_courtesy_n`.
  - `courtesyNumber >= courtesyTotal` → `weekly_report_courtesy_last`.

**Claves de traducción** (flutter-dev, `es-ES.json` y `en-US.json`). **[G]** voz de growth, **[C]** revisión de porty-compliance:

| Clave | es-ES | en-US |
|---|---|---|
| `weekly_report_courtesy_n` **[G][C]** | Informe completo de regalo, {n} de {total}. Con Gold, lo tenés cada semana. | Full report on us, {n} of {total}. With Gold, you get it every week. |
| `weekly_report_courtesy_last` **[G][C]** | Es tu último informe completo de regalo. Con Gold, lo tenés cada semana. | This is your last full report on us. With Gold, you get it every week. |

`weekly_report_courtesy` no cambia.

---

## 4. Tareas por dueño

### porty-backend-dev (primero; independiente)

| Archivo | Qué |
|---|---|
| `supabase/migrations/20261103110000_rollout_flag_sql.sql` (nuevo) | §3.1 (también lo usa la spec de prueba de Premium) |
| `supabase/migrations/20261103120000_weekly_report_courtesy.sql` (nuevo) | §3.2 y §3.3 |
| `supabase/tests/weekly_report_courtesy_db_test.sql` (nuevo) | §5 1–5 |
| `supabase/functions/tests/weekly_report_test.ts` | Ajustar las aserciones de `claimed` con los campos nuevos |
| `docs/runbooks/weekly-report.md` | Cómo prender, cambiar N y la consulta de lectura (regalos por usuario) |

A verificar por el dev: si `_account_purge_before_delete` limpia `users` de las filas de `app_config` por lista de claves, sumar `weekly_report_courtesy` (y que la guardia de `account_deletion_db_test.sql` siga verde). No hay tablas nuevas.

### porty-flutter-dev (puede arrancar contra el contrato; integra cuando backend avise)

| Archivo | Qué |
|---|---|
| `lib/features/weekly_report/domain/weekly_report_claim.dart` | `courtesyNumber`, `courtesyTotal` |
| `lib/features/weekly_report/domain/weekly_report.dart` | Campos, `toJson`, `tryParse`, `compose` |
| `lib/features/weekly_report/providers/weekly_report_controller.dart` | Pasarlos a `compose` |
| `lib/features/weekly_report/view/weekly_report_screen.dart` | Elegir el texto (§3.4) |
| `assets/translations/es-ES.json`, `assets/translations/en-US.json` | 2 claves. **Después** de cerrar las traducciones de la spec sin-callejones (archivo en uso) |
| `test/features/weekly_report/...` (claim, modelo, pantalla; nombres a verificar por el dev) | §5 6–9 |

### porty-assistant-dev

Nada. No toca el chat.

### Orden

`backend` ∥ `flutter (contra el contrato)` → integración con `db reset` local. Las traducciones, después de sin-callejones.

---

## 5. Criterios de aceptación

`psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/weekly_report_courtesy_db_test.sql` imprime `WEEKLY_REPORT_COURTESY_DB_TEST_OK`; `deno test supabase/functions/tests/weekly_report_test.ts`; `flutter test test/features/weekly_report`; `flutter analyze` sin warnings nuevos.

**Backend**
1. `_rollout_bucket` devuelve los 4 valores de la tabla de §3.1.
2. Interruptor apagado: Free reclama la semana A → `claimed, courtesy: true, courtesy_number: 1, courtesy_total: 1`; la semana B → `numbers_only` (idéntico a hoy).
3. Interruptor con el usuario en `users` y `reports: 3`: semanas A, B, C → `courtesy_number` 1, 2, 3 y `courtesy_total` 3; semana D → `numbers_only`. Un usuario que ya tenía 1 regalo recibe 2 más.
4. Con el flag prendido: `reports` ausente o `"x"` → 3; `reports: 0` → 1; `reports: 50` → 8.
5. Gold: `claimed, courtesy: false` sin los campos nuevos. `disabled` sigue ganándole a todo. `supabase db reset` aplica las migraciones dos veces sin error.

**App**
6. `WeeklyReportClaim.parse` lee los campos; con valores raros quedan en null.
7. Un payload guardado sin los campos (versión anterior) se parsea y muestra `weekly_report_courtesy`.
8. Pantalla: 2 de 3 → "Informe completo de regalo, 2 de 3…"; 3 de 3 → "Es tu último informe…"; total 1 → texto de hoy. En inglés, las versiones `en-US`.
9. `toJson` → `tryParse` conserva los dos campos.

**Humo** (porty-qa-engineer, en dev con `users` = cuenta de prueba): tres semanas cubiertas forzando `weekly_reports` (o con el reloj del servidor de dev, a verificar por QA), captura de la pantalla con "2 de 3" y "último" para porty-ui-reviewer (claro y oscuro).

---

## 6. Riesgos y decisiones

**Decisiones**
- **"Primeros N informes", no "primeras N semanas desde el alta"** (el roadmap decía lo segundo). Contar regalos usados no castiga a quien no abrió la app en la semana 2, es el mismo criterio que hoy (`exists courtesy` → `count >= N`) y no necesita la fecha de alta. Efecto: los usuarios viejos que ya usaron su regalo reciben N−1 más al prenderlo. Es valor extra, no recorte; para la lectura, porty-data-analyst excluye las cohortes de alta de las 4 semanas previas al día en que se prende.
- **N en una fila propia** (`weekly_report_courtesy`) con formato `PortyRolloutFlag` + `reports`: se prende primero para una lista de usuarios y no se pisa con el `update` del runbook de `weekly_report`.
- **El servidor decide todo**; la app no lee el interruptor: solo muestra los números que vienen en el claim.
- **Un regalo fallido (3 intentos) cuenta como usado**, igual que hoy. Simplicidad sobre generosidad; si los fallos pasan del 5 % (`weekly_reports.status = 'failed'`), se revisa.
- Helper SQL `_rollout_on` compartido con la spec de prueba de Premium, en su propia migración.

**Riesgos**
- Costo: ~US$0,004 por informe → 2 informes extra ≈ US$0,008 por usuario no Gold, una vez. Despreciable.
- Sin F0 (push), solo lo ven quienes abren la app el fin de semana: menos alcance, misma lógica.
- Si el algoritmo SQL del bucket difiere del de la app, un usuario podría estar "prendido" en un lado y no en el otro; acá solo importa el servidor, pero los vectores de §3.1 lo blindan para la otra spec.

**Textos para porty-compliance:** `weekly_report_courtesy_n` y `weekly_report_courtesy_last` (§3.4).

**Toca el prompt o el catálogo del chat:** **no**. No hay que regenerar la allowlist ni desplegar `ai-chat`.

**Necesita OK del usuario**
1. `db push` de `20261103110000_rollout_flag_sql.sql` y `20261103120000_weekly_report_courtesy.sql`.
2. Publicar la versión de la app con el copy nuevo (la lógica del servidor funciona también con la app vieja: muestra el texto de hoy).
3. Prender `weekly_report_courtesy` en producción (SQL de §3.2), en un día conocido.
4. F0 de Firebase/APNs y prender `app_config.push` (opcional, suma alcance).
