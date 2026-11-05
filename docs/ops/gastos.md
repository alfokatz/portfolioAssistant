# Gastos pendientes de Porty

Lista que usa `porty-chief-of-staff` para el plan diario. Montos de referencia: confirmarlos en cada sitio al pagar (los precios cambian). Marcar `[x]` con la fecha cuando se pague.

Última revisión: 2026-11-04.

## Obligatorios para publicar

- [ ] **Apple Developer Program** — US$99 / año. Sin esto no hay App Store ni TestFlight.
- [ ] **Google Play Developer** — US$25, pago único.
- [ ] **Abogado** — a cotizar, pago único. Revisión de Términos, Privacidad y Borrado de la app; consulta CNV (información vs. asesoramiento en Diagnóstico e informe semanal); uso de marcas (S&P 500, SnapTrade, Binance, eToro). Ver `docs/legal/reviews/`.

## Infraestructura (recurrente)

- [ ] **Supabase Pro** — US$25 / mes. Recomendado al lanzar: en Free el proyecto se pausa tras una semana sin actividad y no hay backups diarios. Define el plazo de backups de la política de privacidad (`backupRetention` en porty-web).
- [ ] **OpenAI (chat)** — variable, ~US$0,006 por consulta (estimado; el real está en `ai_turn_usage`). Free al tope: ≤ US$0,26 por usuario al mes. Ver `docs/business/metrics/2026-11-02-embudo-a-pago.md`.
- [ ] **Dominio `portyassistant.com`** — ~US$10–11 / año en Cloudflare. Pago este año; renovar.
- [ ] **SnapTrade** — a confirmar (suele cobrar por usuario conectado). Revisar el plan antes de que crezca el uso.
- [ ] **Finnhub** — US$0 hoy (plan gratis). Plan pago si crece el uso de Gold (precio a confirmar).

## Comisiones (se descuentan de lo cobrado)

- Apple y Google sobre suscripciones: 15 % con el programa de pequeños desarrolladores de Apple y el esquema de suscripciones de Google; si no, hasta 30 % el primer año. **Tarea:** anotarse en el Small Business Program de Apple.
- RevenueCat: gratis hasta cierto ingreso mensual, después un % chico (confirmar umbral actual).
- Mercado Pago (preventa de la landing): su comisión por cobro.

## Opcionales

- [ ] **Publicidad paga** (Meta, TikTok, Apple Search Ads) — presupuesto a definir después de 2 semanas de orgánico.
- [ ] **Responder desde `@portyassistant.com`** — US$0 con Brevo + "Enviar como" en Gmail, o ~US$7 / mes con Google Workspace.
- [ ] **Sunra (video con IA)** — saldo ~US$1,6; recargar solo si hacen falta más planos generados.

## Sin costo (ya resuelto)

Cloudflare Pages (sitio), Email Routing, Workers (plan gratis), Firebase Cloud Messaging (push).

**Piso para lanzar:** US$99 (Apple) + US$25 (Google) + abogado, idealmente + Supabase Pro (US$25 / mes).
