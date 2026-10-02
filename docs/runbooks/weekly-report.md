# Runbook: informe semanal de Porty

**Plan:** `docs/superpowers/plans/2026-10-01-informe-semanal-porty.md` · **Estado al 2026-10-02:** implementado y probado en local; nada desplegado.

El informe aparece en la Home los sábados (cubre la semana bursátil cerrada) y queda visible hasta el viernes siguiente. Gold ve el informe completo; Free y Premium, la versión con números más un teaser de Gold, y una única vez el completo como degustación. **No gasta consultas.**

## Piezas

| Pieza | Dónde | Qué hace |
|---|---|---|
| Migración `20261002000000_investor_pulse.sql` | `supabase/migrations/` | `super_investors` (lista editable con CIKs de EDGAR verificados) y `investor_pulse_cache` |
| Migración `20261002120000_weekly_reports.sql` | idem | `weekly_reports`, `claim/complete/fail_weekly_report`, `ai_report_begin` y columna `purpose` en `ai_turn_usage` |
| Migración `20261002130000_weekly_report_flag.sql` | idem | **Interruptor** `app_config.weekly_report` (arranca apagado). Redefine el claim y `ai_report_begin` con el chequeo. Va aparte porque la anterior ya estaba aplicada en dev |
| Edge function `investor-pulse` | `supabase/functions/investor-pulse/` | Noticias (Google News) + presentaciones a la SEC de la semana, con caché global |
| `ai-chat`, modo informe | `supabase/functions/ai-chat/handler.ts` + `allowed_report_prompts.json` | Header `x-porty-purpose: weekly_report`: prompt propio, sin tools ni stream, exige claim, no cobra cuota, tope de 6 llamadas por usuario y semana |
| App | `lib/features/weekly_report/` | Datos de la semana, prompt + validador, controller, tarjeta en la Home y pantalla `/weekly-report` |

## Antes de desplegar

- [ ] **`ai-chat` todavía tiene pendiente el deploy del prompt del chat** (`prompt_not_allowed` en la app actual). Este despliegue lo incluye: `allowed_system_prompts.json` ya tiene el hash nuevo.
- [ ] Contacto para la SEC: un mail real del equipo. La SEC exige identificarse (`User-Agent` con contacto); sin él, `investor-pulse` devuelve solo noticias.
- [ ] `OPENAI_API_KEY` ya está en los secrets del proyecto (es la misma del proxy del chat).
- [ ] Revisar la lista de inversores en la migración (o después en la tabla) si negocio quiere cambiarla.

## Orden de despliegue

El orden importa. Una app nueva contra un backend viejo falla en el claim (la RPC no existe) y muestra solo números; un backend nuevo con una app vieja no cambia nada. Igual, conviene ir de atrás para adelante.

1. **Migraciones**
   ```bash
   supabase db push
   ```
   Si todavía no se aplicaron, también suben `20260930000000_weekly_free_analysis`, `20260930120000_ai_proxy` y `20260930130000_app_config`, que son de trabajos anteriores. `app_config` tiene que existir antes que `weekly_reports`, y el orden por fecha ya lo garantiza.

2. **Secret de la SEC**
   ```bash
   supabase secrets set SEC_USER_AGENT="Porty <contacto@tu-dominio>"
   ```

3. **Funciones**
   ```bash
   supabase functions deploy investor-pulse
   supabase functions deploy ai-chat
   ```

4. **Verificación del backend (con el informe todavía apagado)**
   ```sql
   -- el interruptor existe y está apagado
   select value from public.app_config where key = 'weekly_report';   -- {"enabled": false}
   -- la lista de inversores cargó
   select count(*) from public.super_investors where active;           -- 19
   ```
   ```bash
   # investor-pulse responde (con el JWT de una cuenta de prueba)
   curl -s "https://<proyecto>.supabase.co/functions/v1/investor-pulse?week=<lunes de la última semana cerrada>" \
     -H "Authorization: Bearer <jwt>" -H "apikey: <anon key>" | head -c 600
   ```

5. **Publicar la versión de la app** que trae `lib/features/weekly_report/`.

6. **Prender el informe** cuando la versión esté en la calle:
   ```sql
   update public.app_config set value = '{"enabled": true}', updated_at = now()
    where key = 'weekly_report';
   ```

## Apagar (interruptor de emergencia)

```sql
update public.app_config set value = '{"enabled": false}', updated_at = now()
 where key = 'weekly_report';
```

Corta en el acto, también para versiones viejas de la app:
- `claim_weekly_report` devuelve `disabled` y la tarjeta desaparece al próximo armado de la Home.
- `ai_report_begin` rechaza cualquier llamada al LLM en curso.

Los informes ya generados quedan guardados y vuelven a mostrarse al prender.

## Si el informe sale con "Porty no pudo escribir su parte"

La reserva funcionó y falló la llamada al LLM. En la consola de la app (debug) aparece `[WeeklyReport] generation failed for <semana>: <tipo>`:

| Tipo | Causa probable | Qué hacer |
|---|---|---|
| `prompt_not_allowed` | `ai-chat` desplegado sin el hash del prompt actual (o sin el modo informe) | `supabase functions deploy ai-chat` desde el repo actual |
| `disabled` | El interruptor está apagado | Prenderlo (arriba) |
| `not_claimed` | La reserva venció (más de 2 min entre el claim y la llamada) o la sesión cambió | Reintentar; si se repite, revisar la latencia |
| `too_many_rounds` | Se usaron las 6 llamadas de la semana de ese usuario | En dev, resetear (abajo) |
| `unavailable` / `http_5xx` | `OPENAI_API_KEY` o el proxy | Logs de `ai-chat` |

Cada falla gasta un intento: a los 3, la semana queda en `failed` y muestra solo números. **En dev**, para volver a probar con una cuenta:

```sql
delete from public.weekly_reports
 where user_id = (select id from auth.users where email = '<email>')
   and week_start = '<lunes de la semana>';
```

## Checklist en el iPhone

Usar una cuenta de cada plan. Para Free/Premium, la degustación se gasta una sola vez: después hay que usar otra cuenta o borrar su fila de `weekly_reports` en dev.

- [ ] **Gold, primera vez en la semana:** la tarjeta dice "Porty está preparando tu semana…", y entre 5 y 15 s después aparece el titular **con un toque leve**. El alto cambia sin saltos.
- [ ] Al tocar la tarjeta hay un **tick** de selección y se abre el informe; las secciones entran escalonadas. Al volver a abrirlo, aparece sin animar.
- [ ] Links de fuente: abren la nota en el navegador, y el link de la SEC abre la página de la presentación.
- [ ] "Preguntale a Porty" abre el chat con la pregunta.
- [ ] **Otro dispositivo de la misma cuenta:** muestra el mismo informe sin volver a generarlo. En `ai_turn_usage` hay una sola fila `weekly_report` por intento.
- [ ] **Free/Premium, primera vez:** el informe completo con "Este informe completo va de regalo…".
- [ ] **Free/Premium, semana siguiente:** solo números y "Lo que explica tu semana está en Gold". Al tocarlo hay un **toque de bloqueo** y se abre el paywall con "Informe semanal" en la lista de Gold. Free ve además el S&P bloqueado.
- [ ] Sin posiciones: no hay tarjeta.
- [ ] Reduce motion (Ajustes → Accesibilidad → Movimiento): todo aparece en su estado final.
- [ ] Dark mode, y iPhone SE o mini: nada cortado.
- [ ] Interruptor apagado: la tarjeta desaparece al refrescar la Home.

Los haptics no se sienten en el simulador. Los del informe son: `textAnswerRevealed` (Porty terminó), `selectionTap` (abrir, preguntar) y `lockedTap` + `paywallOpened` (teaser). Todos respetan el ajuste de vibraciones de la app.

## Monitoreo

```sql
-- costo del informe por semana (no cuenta como consulta)
select date_trunc('week', created_at) as semana,
       count(*) as llamadas_turno,
       round(sum(cost_usd), 4) as usd
from public.ai_turn_usage
where purpose = 'weekly_report'
group by 1 order by 1 desc;

-- estado de los informes de la última semana
select status, courtesy, count(*), round(avg(llm_rounds), 2) as rondas_promedio
from public.weekly_reports
where week_start = (select max(week_start) from public.weekly_reports)
group by 1, 2;

-- qué trajo investor-pulse
select week_start, fetched_at, jsonb_array_length(items) as items
from public.investor_pulse_cache order by week_start desc limit 4;
```

**Esperado** (evals del 2026-10-02): unos US$0,005 por informe completo; cerca del 35% necesitan una reescritura (2 rondas); `failed` debería ser casi nulo.

**Logs de la función:** `{"fn":"investor-pulse","cache":"hit|miss|stale|error"}`. Si aparece `SEC_USER_AGENT not set`, falta el secret.

## Cambiar el prompt del informe

`lib/features/weekly_report/prompts/weekly_report_prompt.dart` es fijo: el proxy solo acepta su hash.

1. Editar el prompt y correr los evals (abajo).
2. `UPDATE_PROMPT_ALLOWLIST=1 flutter test test/security/system_prompt_allowlist_test.dart`: agrega el hash a `allowed_report_prompts.json`.
3. **Desplegar `ai-chat` antes de publicar la app.** El hash viejo se conserva para las versiones que siguen en la calle.

## Evals (modelo real, proxy local)

```bash
supabase start
supabase functions serve --env-file supabase/functions/.env.local      # key de OpenAI de DEV
# el informe arranca apagado: prenderlo en la base LOCAL
docker exec -i supabase_db_portfolio_assistant psql -U postgres -c \
  "update public.app_config set value='{\"enabled\": true}' where key='weekly_report'"
eval "$(cd supabase && supabase status -o env | grep -E '^(API_URL|SERVICE_ROLE_KEY|ANON_KEY)=' | sed 's/^/export /')"
(cd supabase/functions && deno run -A scripts/eval_report_users.ts 12) > /tmp/report_users.json
RUN_WEEKLY_REPORT_EVALS=1 EVAL_REPORT_USERS=/tmp/report_users.json EVAL_ANON_KEY=$ANON_KEY \
  flutter test test/evals/weekly_report_evals_test.dart
```

Son 11 casos, unos US$0,05 por corrida. Las salidas quedan en `build/weekly_report_evals.json` para leer el tono.

**Screenshots** con fuentes y textos reales:
```bash
RUN_SCREENSHOTS=1 SCREENSHOTS_OUT=/tmp/shots flutter test test/screenshots/weekly_report_screenshots_test.dart
```

## Limitaciones conocidas

- **Fuentes de datos:** Google News RSS y el plan free de Finnhub no son para uso comercial. La alternativa (Marketaux, o Finnhub pago) está en el §9b del plan.
- **Posiciones cerradas en la semana:** el cálculo las soporta, pero la Home todavía no se las pasa.
- **13F:** solo dice "presentó su cartera del trimestre". El diff de qué compró o vendió queda para v2.
- **Push del sábado:** v2 (FCM/APNs más un job en el servidor).
