# Notificaciones y alertas de precio (antecedente)

**Estado:** implementado el 2026-10-10 según
`docs/superpowers/plans/2026-10-10-notificaciones-push.md` (runbook:
`docs/runbooks/push-notifications.md`). Lo de abajo queda como antecedente:
los interruptores se sacaron de Ajustes el 2026-10-07 porque no hacían nada,
y volvieron con el plan nuevo.

## Qué había

En Ajustes → Preferencias había dos interruptores:

- **Notificaciones** (clave `settings_notifications_enabled` en
  SharedPreferences).
- **Alertas de precio** (clave `settings_price_alerts_enabled`).

Los dos arrancaban **prendidos** y solo guardaban el valor en el teléfono:
ninguna parte de la app lo leía. La app no manda notificaciones push ni
locales, y no existe ningún sistema de alertas. El usuario veía "alertas
activas" que no existían.

Se borraron el `SettingsNotifier` y el `SettingsState`, que solo existían
para esos dos valores. Las claves pueden quedar en los teléfonos que ya
abrieron Ajustes; nadie las lee.

## Ojo: las alertas de precio se siguen vendiendo

`plan_matrix.dart` incluye `plan_feature_price_alerts` ("Alertas de
precio") en los `extraMarketingKeys` de **Premium**, así que el paywall y
la card de suscripción la muestran como beneficio. Se dejó así el
2026-09-30 a la espera de una decisión de negocio. Antes de publicar hay
que implementarla o sacarla de la matriz.

## Qué haría falta

### Notificaciones

1. **Permiso:** pedirlo en el momento en que aporta valor (por ejemplo, al
   crear la primera alerta), no al abrir la app. `permission_handler` ya
   está en las dependencias.
2. **Push:** FCM (Android) y APNs (iOS); guardar el token por usuario y
   dispositivo en Supabase (tabla nueva, en una migración nueva).
3. **Contenidos candidatos:**
   - el informe semanal listo (sábado);
   - una alerta de precio disparada;
   - resultados (earnings) de una acción de la cartera al día siguiente
     (Gold).
4. **Ajustes:** volver a agregar el interruptor general, y uno por tipo
   si hay más de uno.

### Alertas de precio (Premium)

1. **Modelo:** tabla `price_alerts` (usuario, ticker, condición
   arriba/abajo, precio objetivo, activa, última vez disparada), con RLS
   por usuario.
2. **Creación:** desde el detalle de una posición ("Avisame si VOO pasa
   $750"), y quizás desde Porty con una tool.
3. **Evaluación del lado del servidor:** un cron (Supabase scheduled
   function) que compara con el precio actual, usando el proxy de
   Finnhub y su caché para no gastar cuota, y manda el push.
4. **Gating:** Premium y Gold, según `PlanMatrix`.
5. **Ajustes:** una fila "Alertas de precio" que lleve a la lista de
   alertas activas, no un interruptor.
