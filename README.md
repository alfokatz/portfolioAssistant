# PortfolioAI

App Flutter para inversores que combina un dashboard de portfolio con flujos conversacionales de UI generada por IA.

## Requisitos

- Flutter SDK 3.35+
- Dart 3.9+

## Configuración

1. Copia las variables en `assets/env/.env.development`:

```env
OPENAI_API_KEY=sk-...   # Opcional: sin key usa UI offline de respaldo
YAHOO_CACHE_TTL_MINUTES=10
```

2. Instala dependencias:

```bash
flutter pub get
```

3. Ejecuta:

```bash
flutter run --dart-define=FLAVOR=development
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
