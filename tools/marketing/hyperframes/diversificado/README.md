# Creés que estás diversificado (HyperFrames)

Video 9:16 de 17,6 s a 60 fps, solo motion design (sin IA generativa). Hecho con la skill `porty-video`.

- Salida: `docs/marketing/social/piezas/2026-11-12/diversificado.mp4`
- Renderizar: `npm run render` (Node 22+ y FFmpeg; en el entorno cloud, con `PUPPETEER_EXECUTABLE_PATH=/opt/pw-browsers/chromium`). Revisar: `npm run check` y `npm run snapshot`.
- Valor que muestra: Diagnóstico de cartera (plan gratis): mira adentro de los fondos y marca concentración y solapamiento que a simple vista no se ven.

## Guion

| Tiempo | Escena | Texto en pantalla | Qué pasa |
|---|---|---|---|
| 0–5,2 s | `cards` | "Con 6 inversiones distintas, ¿estás diversificado?" → Porty: "Dejame mirar adentro de tus fondos." | 6 tarjetas genéricas; los fondos se abren y sueltan fichas de tecnología que se juntan con las acciones tech |
| 4,6–12,1 s | `diag` | "Porty mira adentro de tus fondos." · "Y te marca lo que no se ve a simple vista." | Pantalla "Miré tu cartera" (textos reales del diagnóstico): "Tecnología es el 52% de tu cartera" (barra de 30 % a 52 %) y "Una empresa pesa 18% de tu cartera" (directa 8 % + en tus ETFs 10 %) |
| 13,4–17,6 s | `outro` | "Próximamente en App Store y Google Play." · "Vas a poder descargarla gratis." | Porty con anteojos sobre el piso |


## Formato (v2, igual al reel "Hola, soy Porty")

- Piso cálido desde y = 1470 px: Porty (o la taza) se para encima y el teléfono queda apoyado detrás, así la mitad de abajo no queda vacía y no hay texto en la zona que tapa la interfaz de la red.
- Sin letra chica suelta: chip "Datos de ejemplo" en cada tarjeta con números (aprobado por `porty-compliance` solo para uso orgánico; si se pauta, vuelve a revisión). Sin notas de "Porty usa IA…" ni de plan (decisión del fundador: están en Términos y Condiciones).
- Cierre común: "Próximamente en App Store y Google Play." · "Vas a poder descargarla gratis." · "Algunas funciones son de planes pagos. No es asesoramiento financiero." (sin lista de espera).
- Pantallas con datos más lentas para que se lean.

## Pendiente antes de publicar
- Música desde la biblioteca comercial de TikTok/Instagram al subirlo (el render trae solo efectos).

Calidad v2: `check` sin errores; 1.045 de 1.056 cuadros únicos; ningún tramo quieto > 0,08 s.
