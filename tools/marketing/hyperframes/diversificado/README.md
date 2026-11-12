# Creés que estás diversificado (HyperFrames)

Video 9:16 de 16,5 s a 60 fps, solo motion design (sin IA generativa). Hecho con la skill `porty-video`.

- Salida: `docs/marketing/social/piezas/2026-11-12/diversificado.mp4`
- Renderizar: `npm run render` (Node 22+ y FFmpeg; en el entorno cloud, con `PUPPETEER_EXECUTABLE_PATH=/opt/pw-browsers/chromium`). Revisar: `npm run check` y `npm run snapshot`.
- Valor que muestra: Diagnóstico de cartera (plan gratis): mira adentro de los fondos y marca concentración y solapamiento que a simple vista no se ven.

## Guion

| Tiempo | Escena | Texto en pantalla | Qué pasa |
|---|---|---|---|
| 0–5,2 s | `cards` | "Con 6 inversiones distintas, ¿estás diversificado?" → Porty: "Dejame mirar adentro de tus fondos." | 6 tarjetas genéricas; los fondos se abren y sueltan fichas de tecnología que se juntan con las acciones tech |
| 4,6–12,1 s | `diag` | "Porty mira adentro de tus fondos." · "Y te marca lo que no se ve a simple vista." | Pantalla "Miré tu cartera" (textos reales del diagnóstico): "Tecnología es el 52% de tu cartera" (barra de 30 % a 52 %) y "Una empresa pesa 18% de tu cartera" (directa 8 % + en tus ETFs 10 %) |
| 11,9–16,5 s | `outro` | "El diagnóstico está en el plan gratis." · "Descargala gratis. Algunas funciones son de planes pagos." | Porty con anteojos |

Letra chica (regla de compliance del 2026-11-12): "Imagen ilustrativa con datos de ejemplo." fija desde el segundo 0 y, en los últimos 3 s, "Imagen ilustrativa con datos de ejemplo. No es asesoramiento financiero."

## Pendiente antes de publicar
- Música desde la biblioteca comercial de TikTok/Instagram al subirlo (el render trae solo efectos).
- Revisión final de `porty-compliance` sobre el video renderizado (el copy ya fue revisado el 2026-11-12).
