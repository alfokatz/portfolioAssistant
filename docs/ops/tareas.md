# Tareas del fundador

Lista maestra que mantiene `porty-chief-of-staff`. Prioridad: **P0** bloquea el release · **P1** esta semana · **P2** este mes · **P3** algún día. Quién: **F** = fundador · **A** = un agente (el chief of staff se la delega solo, salvo que necesite tu autorización).

Última revisión: 2026-11-04.

## Release 1 a las tiendas (bloqueantes)

- [ ] P0 · F · **Productos anuales**: crear `portfolio_premium_annual` y `portfolio_gold_annual` en App Store Connect y Google Play (sin ofertas introductorias) y sumarlos a los offerings de RevenueCat; decidir el precio (propuesta: 10× el mensual). La revisión de las tiendas tarda. — `docs/product/roadmap.md`
- [ ] P0 · F · **Consulta de solo lectura en producción** antes del `db push` del borrado: confirmar que `positions`/`closed_positions` borran en cascada. — `docs/runbooks/account-deletion.md`
- [ ] P0 · F · **`db push`** de las migraciones nuevas (20261102120000, 120100, 120200, 130000; 20261103110000, 120000, 130000). — runbooks
- [ ] P0 · F · **Deploy** de `revenuecat-webhook` y `delete-account` (después del `db push`). `ai-chat` no cambió.
- [ ] P0 · F · **Verificar secretos** en Supabase (`supabase secrets list`): `REVENUECAT_SECRET_API_KEY` (v1 `sk_`), `SNAPTRADE_CLIENT_ID`, `SNAPTRADE_CONSUMER_KEY`, `ETORO_CLIENT_ID`, `ETORO_CLIENT_SECRET`.
- [ ] P0 · F · **Publicar porty-web** en Cloudflare Pages con el dominio `portyassistant.com` (incluye `/app/privacidad`, `/app/terminos`, `/borrar-cuenta`). Claude puede hacer el deploy si lo pedís.
- [ ] P0 · F · Completar en porty-web `src/config/site.ts`: `legalEntity` (razón social y domicilio) y `backupRetention` (plazo de backups de tu plan de Supabase).
- [ ] P0 · F · **Abogado**: revisar Términos, Privacidad y Borrado de la app; si el Diagnóstico y el informe semanal quedan del lado de "información" (CNV); uso de marcas S&P 500, SnapTrade, Binance, eToro. — `docs/legal/reviews/`
- [ ] P0 · F · **App Store Connect**: URL de privacidad (`portyassistant.com/app/privacidad`) y EULA estándar o Términos. **Play Console**: Data safety y URL de borrado (`portyassistant.com/borrar-cuenta`).
- [ ] P0 · F · **Aprobar el PR** de la rama `claude/porty-dev-agents` (revisión final y merge). Pedí: "abrí el PR de claude/porty-dev-agents".
- [ ] P1 · F · **Firebase/APNs** para push (revisar antes el bundle id de iOS). Sin esto no llega el aviso del sábado. — `docs/runbooks/push-notifications.md`
- [ ] P1 · F · Build con `APPLE_SIGN_IN_ENABLED=true` (checklist de rename) y probar el toast de revocación de Apple al borrar la cuenta.
- [ ] P1 · F · Prueba de humo en TestFlight / Play internal (comprar, restaurar, borrar cuenta, paywall anual). Pedí a Claude el checklist de QA.
- [ ] P2 · A · Cambiar "Calificar la app" en Ajustes (hoy apunta a `portfolioai.app/rate`) por la ficha o el diálogo de calificación de la tienda.

## Lanzamiento y marketing

- [ ] P1 · F · **Link de descarga con UTM** por red (o un link en la bio que detecte el teléfono). Sin esto no se mide de dónde vienen las descargas. — plan de redes §7
- [ ] P1 · F · Crear las cuentas de **Instagram y TikTok** de Porty y cargar los handles en porty-web (`site.ts → social`).
- [ ] P1 · F · Publicar la **semana 1 de presentación**: PR1 (video), PR2 (carrusel), PR3 (Conocé a Porty), PR5 (stories), con música de la biblioteca y etiqueta de contenido con IA en los videos con planos generados. — `docs/marketing/social/piezas/2026-11-03/README.md`
- [ ] P1 · F · Subir los 4 **cortes por función** escalonados (informe semanal, comparar, diversificar, metas). — `docs/marketing/social/piezas/2026-11-03/cortes/`
- [ ] P2 · A · Revisión de compliance del corte "diversificar" antes de pautarlo. Pedí: "que compliance revise el corte de diversificar".
- [ ] P2 · F · Grabar las tomas reales de pantalla con cuenta demo para P3, P5, P10 y P12 (lista en el plan de redes §4).
- [ ] P2 · F · Definir presupuesto de ads (después de 2 semanas de orgánico) y si conviene un plan de video IA (Sunra tiene ~US$1,6).

## Métricas y decisiones

- [ ] P1 · F · Correr las consultas SQL Q1–Q8 en producción y `select key, value from app_config;`. — `docs/business/metrics/2026-11-02-embudo-a-pago.md`
- [ ] P2 · F · **23/11**: primera lectura del % de altas que pagan en 14 días (pedí a Claude que la analice con los resultados).
- [ ] P2 · F · **Semana 4**: prender los interruptores en `app_config` (`broker_screenshot_exit`, `diagnosis_bridge`, `quota_nudge`, `weekly_report_courtesy`, `market_taste`).
- [ ] P2 · F · **27/11**: decidir si se levanta la decisión de no hacer prueba de Gold en diciembre. — `docs/product/decisions.md`

## Infraestructura

- [x] 2026-11-04 · Email Routing: `soporte@`, `privacidad@`, `hola@`, `admin@` → Gmail.
- [ ] P2 · F · Probar que llega un mail a `soporte@portyassistant.com` desde otra cuenta.
- [ ] P2 · F · Responder desde el dominio: "Enviar como" en Gmail con SMTP (Brevo gratis) o Google Workspace.
- [x] 2026-11-04 · Sacar los subdominios de Email Routing que sobran (`admin.` y `soporte.portyassistant.com`).
