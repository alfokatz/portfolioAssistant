# Runbook: conexión con Binance (solo lectura)

Estado al 2026-10-16: **implementado y probado en local** (tests de Deno con Binance falso y test SQL contra Postgres). **Nada desplegado.**

Plan: F6 de `docs/superpowers/plans/2026-10-16-porty-siguiente-nivel.md`.

## 0. Antes de desplegar (bloqueante)

1. **Región.** Binance responde HTTP 451 desde algunas regiones (entre ellas EE.UU.). Las edge functions corren en la región del proyecto de Supabase. Probar desde la función ya desplegada:
   ```bash
   curl -sS -X POST "https://<project-ref>.supabase.co/functions/v1/binance-sync/sync" \
     -H "Authorization: Bearer <jwt de un usuario de prueba conectado>"
   ```
   Si devuelve `binance_region_blocked`, no lanzar: o se mueve el proyecto, o se configura `BINANCE_API_URL` con un endpoint que Binance permita desde esa región (ver su documentación de endpoints alternativos), o se descarta la integración.
2. **Términos de Binance** para el uso de la API por un tercero con claves de los usuarios: revisarlos (igual que con eToro).
3. **Política de privacidad** y formularios de las tiendas: "Financial info" ya está declarado por eToro; agregar Binance como origen.

## 1. Arquitectura

| | App | Servidor |
|---|---|---|
| Conectar | Ajustes → Cuentas conectadas → Binance. El usuario crea una clave **solo de lectura** en Binance (los pasos están en la pantalla) y pega la clave y el secreto | `POST binance-sync/connect {api_key, api_secret}`: `GET /sapi/v1/account/apiRestrictions` firmado. **Rechaza la clave si puede operar, retirar o transferir** (`binance_write_permissions`), sin guardar nada. Si es de solo lectura, la guarda en Vault, marca la conexión e importa |
| Sincronizar | Al abrir la app o volver a ella (si lo último tiene más de 30 min) y con "Actualizar ahora" | `POST binance-sync/sync`: como mucho una cada 5 min (si no, devuelve la última), lease por usuario y `binance_apply_sync` atómico |
| Leer estado | `select` de `binance_connections` (RLS: la suya) | — |
| Desconectar | Hoja "¿Qué hacemos con lo importado?" | `POST binance-sync/disconnect {keepAsManual}`: borra la clave de Vault y convierte en manuales o borra las filas `binance` |

- Las posiciones viven en `positions` con `source='binance'`, ticker de Yahoo `BTC-USD` y `broker_price` (el precio de Binance, de respaldo si Yahoo no cotiza el activo).
- El trigger `_etoro_rows_read_only` ahora cubre todo lo que no es manual (error `broker_rows_are_read_only` para Binance; el de eToro no cambió).
- **Qué se importa:** saldo libre + bloqueado de cada activo. Lo de Simple Earn flexible (`LDBTC`) suma al activo. No se importan las stablecoins ni las monedas (`cash`), los saldos de menos de USD 1 (`dust`) ni lo que no tiene precio en Binance (`no_price`).
- **Precio de compra:** costo promedio de las operaciones en `{ACTIVO}USDT` y `{ACTIVO}USDC` (las últimas 1000 por par, para los 15 activos de más valor). Si las operaciones no explican al menos la mitad de lo que tiene (lo compró en otro par o lo transfirió), se usa el precio del momento y la app lo avisa (`estimatedCost`).
- Peso en el límite de Binance por sincronización: cuenta (20) + precios (4) + hasta 30 consultas de operaciones (20 c/u) ≈ 624 de 6000 por minuto.

Secrets de `binance-sync`: ninguno obligatorio. `BINANCE_API_URL` es opcional (por defecto `https://api.binance.com`).

## 2. Desplegar

```bash
supabase db push            # 20261016000400_binance_sync.sql
supabase functions deploy binance-sync
```

## 3. Probar

1. Crear una clave de solo lectura en una cuenta de Binance de prueba.
2. Ajustes → Binance → pegarla → "Conectar Binance". Tiene que aparecer "Importamos N criptomonedas" y las posiciones en Inicio con la marca "Binance".
3. Crear otra clave con "Habilitar trading spot" → tiene que rechazarla con el mensaje de solo lectura, sin guardar nada (`select * from binance_keys` vacío para ese usuario).
4. Borrar la clave en Binance y tocar "Actualizar ahora" → "Hay que reconectar"; lo importado sigue en pantalla.
5. Desconectar con "Conservarlas como manuales" → se pueden editar. Volver a conectar y desconectar con "Borrarlas" → solo se van las de Binance.

Tests:

```bash
cd supabase/functions && deno test --allow-env tests/binance_sync_test.ts
psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/binance_sync_db_test.sql
flutter test test/features/binance
```

## 4. Seguridad y datos

- **Clave:** cifrada en Vault (`binance_keys` guarda solo el puntero). Nunca vuelve a la app ni va a los logs (los logs dicen qué pasó, sin ids ni claves). En la app solo se ve `…ab12` (`api_key_hint`).
- **Solo lectura, verificado:** si la clave puede operar, retirar o transferir, se rechaza antes de guardarla. Si después el usuario le agrega permisos en Binance, Porty no lo detecta hasta reconectar: igual nunca llama a nada que no sea de lectura.
- **Retención:** al desconectar se borra la clave en el momento. Al borrar la cuenta de Porty se borra todo (`on delete cascade`).

## 5. Apagar

- Para todos: no hay secreto que borrar. Desplegar la función con `handlerConfig.allowedTiers = []` (responde `binance_plan_required`) o quitar la entrada de Ajustes en la app.
- Antes de borrar las tablas: `select binance_disconnect(user_id, true) from binance_connections where status <> 'disconnected';`.
