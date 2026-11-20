# Importar extractos: qué formatos fallan

`statement-import` deja una línea JSON por archivo en los logs de la función. Nunca lleva contenido ni el nombre del archivo: solo la extensión, el resultado y una huella anónima del formato (`statement-import/fingerprint.ts`).

```json
{"fn":"statement-import","kind":"text","ext":"csv","source":"ai","rows":12,
 "fmt":{"hash":"3fa9c01b22de","cols":9,"known":"symbol|?|quantity|price|?|?|costbasis|?|?"}}
```

| Campo | Qué es |
|---|---|
| `kind` | `text`, `xlsx`, `pdf`, `image`, `note`, `unsupported` |
| `ext` | extensión del archivo si es conocida, si no `other` |
| `source` | `csv` = lo leyó el lector sin IA (gratis); `ai` = cobró una consulta |
| `format` | con `source: csv`: `generic` o `ibkr` |
| `rows` | posiciones que salieron (0 = la IA no encontró nada) |
| `outcome` / `error` | `unsupported_type`, `quota_exceeded`, `unavailable`… |
| `sheets` | hojas del `.xlsx` |
| `fmt.hash` | mismos encabezados → mismo hash (agrupa un formato de bróker) |
| `fmt.known` | los encabezados, con `?` en los que el lector no conoce |

## Qué mirar

Los `kind: text` o `xlsx` con `source: ai` son archivos que el lector sin IA no entendió: le costaron una consulta al usuario (o lo frenaron si no tenía cupo, `outcome: quota_exceeded`). Agrupados por `fmt.hash`, los más repetidos son los formatos a sumar.

En Supabase → Logs Explorer (ajustar si cambia el esquema de `function_logs`):

```sql
select
  json_value(event_message, '$.fmt.hash') as hash,
  json_value(event_message, '$.fmt.known') as known,
  json_value(event_message, '$.ext') as ext,
  count(*) as n
from function_logs
where json_value(event_message, '$.fn') = 'statement-import'
  and json_value(event_message, '$.source') = 'ai'
  and json_value(event_message, '$.kind') in ('text', 'xlsx')
  and timestamp > timestamp_sub(current_timestamp(), interval 30 day)
group by hash, known, ext
order by n desc
limit 20
```

## Sumar un formato

`known` muestra qué columnas reconoce y dónde hay `?`. Para saber qué dicen esos `?` hace falta un exporte de ejemplo de ese bróker (de una cuenta de prueba o de un usuario que lo comparta): los logs no lo guardan a propósito.

- Si solo faltan nombres de columna: agregarlos a `synonyms` en `statement-import/parse_csv.ts`.
- Si el archivo tiene otra estructura (varias secciones, como Interactive Brokers): un lector propio como `ibkrPositions`.
- Siempre con un test en `supabase/functions/tests/statement_import_test.ts` armado con las columnas del exporte real (sin datos de nadie).
