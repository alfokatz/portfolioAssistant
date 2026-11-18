# Porty

App Flutter para inversores que combina un dashboard de portfolio con flujos conversacionales de UI generada por IA.

## Requisitos

- Flutter SDK 3.35+
- Dart 3.9+

## Configuración

1. Copiá `env/develop.json.example` a `env/develop.json` y cargá la URL y la anon key de la branch develop de Supabase (ver `docs/runbooks/build-entornos.md`). Las claves de OpenAI y Finnhub viven en las edge functions, nunca en la app.

> **Para probar calendario de resultados / noticias en local hacen falta DOS cosas, no solo la key:**
> 1. `FINNHUB_API_KEY` cargada en los secretos de la edge function `finnhub` (sin ella, la llamada falla y Porty dice que no pudo consultar ahora mismo).
> 2. La cuenta con la que probás debe tener tier **Gold** en la tabla `user_subscriptions` de Supabase — no hay ningún override de debug para esto en el código. Una cuenta nueva sin compra es `free` por defecto, y con `free`/`premium` Porty dice explícitamente que la función no está en tu plan (no sugiere que falte información). Para subir a Gold un usuario de prueba sin pasar por una compra real, actualizá esa fila directamente en Supabase (requiere la service-role key).
>
> Sin ninguna de las dos cosas, la app no crashea (degrada bien), pero el mensaje que ves depende de cuál falte: revisá `news_enrichment`/`earnings_calendar_status` en el snapshot (`ok`/`empty`/`failed`/`locked`) para saber cuál es.

2. Instala dependencias:

```bash
flutter pub get
```

3. Ejecuta:

```bash
# iOS
flutter run --dart-define-from-file=env/develop.json
# Android: el flavor elige el applicationId (development | staging | production)
flutter run --flavor development --dart-define-from-file=env/develop.json
```

## Arquitectura

- **Clean Architecture**: `domain` → `infraestructure` → `presentation`
- **Estado**: Riverpod (`hooks_riverpod`)
- **Persistencia**: Hive (posiciones locales)
- **Cotizaciones**: Yahoo Finance vía `yahoo_finance_data_reader` (API no oficial)
- **GenUI**: capa propia (`lib/genui/`) con catálogo de widgets y OpenAI JSON mode (compatible con SDK actual; migrar a `genui` oficial cuando Flutter ≥ 3.35.7)

## Flujos

| Pantalla | Ruta |
|----------|------|
| Home | `/Home` |
| Agregar posición | `/position/add` |
| Análisis IA | `/genui/analysis` |
| Inversión IA | `/genui/invest` |
| Planificación IA | `/genui/plan` |

## Disclaimer MVP

- No ejecuta órdenes reales en el mercado
- Sin autenticación (datos solo en dispositivo)
- La API de Yahoo puede fallar; el CRUD local sigue funcionando
