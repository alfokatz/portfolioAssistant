# Runbook: notificaciones push y alertas de precio

**Plan:** `docs/superpowers/plans/2026-10-10-notificaciones-push.md` · **Estado al 2026-10-10:** implementado y probado en local (tests de Deno, SQL y Flutter); nada desplegado. Falta la configuración de Firebase/APNs (F0), que no está en el repo.

## Piezas

| Pieza | Dónde | Qué hace |
|---|---|---|
| Migración `20261011000000_push_notifications.sql` | `supabase/migrations/` | `push_devices`, `notification_preferences`, `notification_outbox`, `notification_log`, interruptor `app_config.push` (arranca **apagado**), RPCs del despacho, `pg_cron`/`pg_net` |
| Migración `20261011010000_price_alerts.sql` | idem | `price_alerts` (tope por plan con trigger: Free 1, Premium 20, Gold 50 en `plan_limits.price_alerts`), pausa/reactivación al cambiar de plan, `market_quotes`, `price_alerts_record` |
| Migración `20261011020000_market_moves.sql` | idem | `market_watch_holdings`, `market_enqueue_moves` (no repetir, agrupar, combinar con la cartera) |
| Migración `20261011030000_push_producers.sql` | idem | Trigger de eToro desconectado (aviso a las 6 h si sigue así), `push_users_at_local_hour`, `push_enqueue` |
| `notify-dispatch` | `supabase/functions/notify-dispatch/` | Toma el outbox, aplica interruptor, preferencias, plan, antigüedad, silencio y tope (3 automáticas/24 h), arma el texto (es/en) y manda por FCM HTTP v1 |
| `market-watch` | `supabase/functions/market-watch/` | Cada 5 min con el mercado abierto: precios en lote (Yahoo `v7/quote`, Finnhub de respaldo), alertas y movimientos fuertes |
| `daily-jobs` | `supabase/functions/daily-jobs/` | Cada hora: informe del sábado 9:00 local, earnings de mañana 19:00 y resultados 12:00/19:00 (Gold), limpieza 04:00 UTC |
| `_shared/yahoo_session.ts` | `supabase/functions/_shared/` | La sesión cookie + crumb de Yahoo, ahora compartida por `yahoo` y `market-watch` |
| `ai-chat` | `allowed_system_prompts.json` | Hash del prompt nuevo de Porty (tools `propose_price_alert` y `list_price_alerts`) |
| App | `lib/features/notifications/` | FCM, registro del token, deep links, Ajustes → Notificaciones, Alertas de precio, hoja de crear alerta, pantalla previa al permiso |

## F0: configuración fuera del repo (una sola vez)

1. **Firebase:** crear el proyecto (solo se usa Cloud Messaging). Registrar:
   - la app Android con `com.portfolioassistant.app` → bajar `google-services.json` a `android/app/`;
   - la app iOS con el bundle id del target Runner → bajar `GoogleService-Info.plist` a `ios/Runner/` y agregarlo al target en Xcode.

   > ⚠️ **Revisar el bundle id de iOS antes de registrar la app.** En `ios/Runner.xcodeproj/project.pbxproj` hoy figura `uy.gub.bps.movil.bpsfuncionarios`, que parece venir de otro proyecto. Firebase y la clave de APNs se configuran con ese id.

   Sin esos dos archivos la app compila y funciona igual, sin push (`FirebasePushMessaging.create` devuelve `NoopPushMessaging` y el plugin de Gradle no se aplica).

   Decidir si se commitean (no son secretos, pero identifican el proyecto). Si no se commitean, el CI de builds tiene que copiarlos.
2. **APNs:** en developer.apple.com, crear una clave `.p8` con "Apple Push Notifications service" y subirla a Firebase (Project settings → Cloud Messaging → Apple app configuration). En el App ID, habilitar la capability **Push Notifications**. El entitlement `aps-environment` ya está en `ios/Runner/Runner.entitlements`.
3. **Opcional, time-sensitive:** para que las alertas de precio atraviesen el modo Concentración, habilitar "Time Sensitive Notifications" en el App ID y agregar a `Runner.entitlements`:
   ```xml
   <key>com.apple.developer.usernotifications.time-sensitive</key>
   <true/>
   ```
   **No agregarlo sin habilitarlo antes en el App ID: rompe la firma.** Sin el entitlement, las alertas llegan igual, como notificación normal.
4. **Service account de FCM:** Google Cloud → IAM → service account con el rol "Firebase Cloud Messaging API Admin" → clave JSON.

## Orden de despliegue

1. **Secrets**
   ```bash
   supabase secrets set FCM_SERVICE_ACCOUNT="$(cat service-account.json)"
   supabase secrets set CRON_SECRET="$(openssl rand -hex 32)"
   # FINNHUB_API_KEY ya existe (proxy finnhub)
   ```
2. **Migraciones** (con `app_config.push` apagado):
   ```bash
   supabase db push
   ```
3. **Funciones**
   ```bash
   supabase functions deploy notify-dispatch
   supabase functions deploy market-watch
   supabase functions deploy daily-jobs
   supabase functions deploy yahoo      # usa el módulo de sesión compartido
   supabase functions deploy ai-chat    # hash del prompt nuevo: ANTES de publicar la app
   ```
4. **Agenda (pg_cron).** Desde el SQL editor. El secreto y la URL van en Vault, no en el texto del job:
   ```sql
   select vault.create_secret('https://<proyecto>.supabase.co', 'project_url');
   select vault.create_secret('<el mismo CRON_SECRET>', 'cron_secret');

   create or replace function public._call_function(p_name text, p_body jsonb default '{}'::jsonb)
   returns void language sql security definer set search_path = public as $$
     select net.http_post(
       url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
              || '/functions/v1/' || p_name,
       headers := jsonb_build_object(
         'Content-Type', 'application/json',
         'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')),
       body := p_body,
       timeout_milliseconds := 55000);
   $$;
   revoke all on function public._call_function(text, jsonb) from public, anon, authenticated;

   -- Lo diferido (silencio, eToro a las 6 h) y lo que no salió en el momento.
   select cron.schedule('push-dispatch', '* * * * *', $$select public._call_function('notify-dispatch')$$);
   -- 13–21 UTC cubre 9:30–16:10 en Nueva York con y sin horario de verano;
   -- la función mira el reloj de NY y no hace nada fuera de horario.
   select cron.schedule('push-market-watch', '*/5 13-21 * * 1-5', $$select public._call_function('market-watch')$$);
   select cron.schedule('push-daily-jobs', '0 * * * *', $$select public._call_function('daily-jobs')$$);
   ```
5. **Verificación del backend** (con push todavía apagado):
   ```sql
   select value from public.app_config where key = 'push';             -- {"enabled": false, ...}
   select tier, price_alerts from public.plan_limits order by tier;     -- free 1, gold 50, premium 20
   select jobname, schedule from cron.job where jobname like 'push-%';
   ```
   ```bash
   curl -s -X POST "https://<proyecto>.supabase.co/functions/v1/market-watch" \
     -H "x-cron-secret: $CRON_SECRET" -d '{"force": true}'
   # {"phase":"…","symbols":…,"quotes":…,…}
   ```
6. **Publicar la app.** Las versiones viejas no registran token: no reciben nada.
7. **Prender para el equipo** (el resto sigue sin recibir):
   ```sql
   update public.app_config
      set value = jsonb_set(value, '{allow_users}', '["<uuid>", "<uuid>"]'), updated_at = now()
    where key = 'push';
   ```
8. **Prender para todos**, cuando el checklist de abajo esté bien:
   ```sql
   update public.app_config set value = jsonb_set(value, '{enabled}', 'true'), updated_at = now()
    where key = 'push';
   ```

## Apagar

```sql
-- Todo (corta en el acto; lo pendiente queda como skipped/push_disabled):
update public.app_config set value = jsonb_set(value, '{enabled}', 'false'), updated_at = now()
 where key = 'push';

-- Un solo tipo (p. ej. los movimientos fuertes si hay quejas):
update public.app_config set value = jsonb_set(value, '{kinds,big_move}', 'false'), updated_at = now()
 where key = 'push';
```

Tipos: `price_alert`, `big_move`, `big_move_digest`, `portfolio_move`, `weekly_report`, `etoro_reconnect`, `earnings_tomorrow`, `earnings_result`, `test`.

Para frenar también la evaluación del mercado (no solo el envío): `select cron.unschedule('push-market-watch');`.

## Checklist en el teléfono

Push real: iPhone físico (el simulador recibe push remotas solo en Macs con Apple silicon o chip T2). Con una cuenta del equipo en `allow_users`.

- [ ] Ajustes → Notificaciones → "Activar notificaciones": aparece la hoja de Porty y, al tocar "Activar", el diálogo del sistema.
- [ ] "Enviarme una de prueba": llega en menos de un minuto; al tocarla abre Ajustes → Notificaciones.
- [ ] Con la app abierta, la de prueba se ve igual (banner del sistema en iOS, notificación local en Android).
- [ ] Crear una alerta desde el detalle de una posición (campana arriba a la derecha) apenas arriba del precio actual. La primera vez ofrece el permiso.
- [ ] Forzar `market-watch` (`{"force": true}`) o esperar al mercado: llega "VOO pasó $X". Al tocarla abre el detalle de la posición (o la lista de alertas si no la tiene).
- [ ] La alerta queda en "Cumplidas"; "Volver a activar" la rearma.
- [ ] Free: la segunda alerta abre el paywall de alertas.
- [ ] Porty: "avisame si Apple baja de 200" → card "Alerta de precio" → "Crear alerta" → "Ver mis alertas".
- [ ] Horario de silencio: poner uno que incluya la hora actual y mandar la de prueba (no respeta el silencio). Forzar un movimiento: no llega.
- [ ] Cerrar sesión: el dispositivo desaparece de `push_devices`.
- [ ] Android 13+: el permiso se pide (POST_NOTIFICATIONS) y los canales aparecen en Ajustes del sistema (Alertas de precio, Tu cartera, Informes, Cuenta).
- [ ] Dark mode y texto grande en Ajustes → Notificaciones y Alertas de precio.

## Monitoreo

```sql
-- Qué pasó con lo que se generó hoy, por tipo
select kind, status, coalesce(skip_reason, '') as motivo, count(*)
  from public.notification_outbox
 where created_at > now() - interval '1 day'
 group by 1, 2, 3 order by 1, 2;

-- Tasa de apertura por tipo (últimos 30 días)
select kind, count(*) as enviadas,
       round(100.0 * count(opened_at) / count(*), 1) as pct_abiertas
  from public.notification_log
 where sent_at > now() - interval '30 days'
 group by 1 order by 2 desc;

-- Usuarios que apagaron cada tipo (la señal de ruido del plan §9)
select count(*) filter (where not big_moves) as sin_movimientos,
       count(*) filter (where not portfolio_moves) as sin_cartera,
       count(*) filter (where not price_alerts) as sin_alertas,
       count(*) filter (where not enabled) as sin_nada,
       count(*) as total
  from public.notification_preferences;

-- Alertas por estado y por plan
select coalesce(public._effective_tier(user_id), 'free') as plan, status, count(*)
  from public.price_alerts group by 1, 2 order by 1, 2;

-- Frescura de los precios del servidor
select count(*), max(fetched_at), min(fetched_at) from public.market_quotes;
```

**Logs de las funciones:** una línea JSON por corrida.
- `{"fn":"market-watch","phase":"open","symbols":…,"quotes":…,"alertsFired":…,"movesQueued":…}`. Si `quotes` cae a 0 con `symbols` > 0, Yahoo está bloqueando la IP del servidor (ver "Fuente de precios").
- `{"fn":"notify-dispatch","sent":…,"skipped":{…},"invalidTokens":…}`.
- `{"fn":"daily-jobs","queued":{…}}`.

## Fuente de precios (decisión D3, pendiente antes del lanzamiento comercial)

`market-watch/quotes.ts` usa Yahoo `v7/finance/quote` (no oficial) y Finnhub `/quote` (plan free) de respaldo. Ninguno de los dos es para uso comercial. Una alerta que no llega porque la fuente cortó es justo lo que rompe la confianza, así que antes de abrirlo a todos hay que pasar a una fuente con licencia (Finnhub pago, Polygon, Twelve Data). Cambia solo `quotes.ts`.

## Tests

```bash
# Edge functions (sin red ni base)
cd supabase/functions
deno test --allow-env tests/notify_dispatch_test.ts tests/market_watch_test.ts tests/daily_jobs_test.ts

# SQL (contra una base con las migraciones: supabase start, o Postgres con stubs)
psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/push_notifications_db_test.sql   # PUSH_DB_TEST_OK

# App
flutter test test/features/notifications test/features/assistant
```

## Limitaciones conocidas

- **Solo mercado de EE.UU.** y sin cripto (decisión D4). Las alertas de tickers de otros mercados se evalúan en el horario de EE.UU.
- **Feriados:** el reloj no los conoce; ese día Yahoo no está en `REGULAR` y los movimientos no se evalúan (las alertas sí, contra el último precio).
- **Hasta 5 minutos de demora** en las alertas (la frecuencia del cron).
- **Tope diario:** 24 h corridas, no el día calendario del usuario.
- **Zona horaria:** la del dispositivo que abrió la app más recientemente.
