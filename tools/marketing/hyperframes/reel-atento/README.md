# Reel "Porty está atento" (HyperFrames)

Video 9:16 de 22,2 s a 60 fps, en formato de red social (no demo). Hecho con [HyperFrames](https://github.com/heygen-com/hyperframes) siguiendo las skills `hyperframes`, `hyperframes-cli` y `media-use` (`.claude/skills/`).

- Salida: `docs/marketing/ads/piezas/2026-11-11/reel_porty_atento.mp4`
- Renderizar: `npm run render` (Node 22+ y FFmpeg; en el entorno cloud, con `PUPPETEER_EXECUTABLE_PATH=/opt/pw-browsers/chromium`).
- Revisar: `npm run check` y `npm run snapshot`.

## Guion

| Tiempo | Escena | Texto en pantalla | Qué pasa |
|---|---|---|---|
| 0–5,6 s | `hook` | "Vos, mirando tu cartera por la 7.ª… 14.ª vez hoy." → Porty: "Tranqui. Yo miro tu cartera por vos." | La app se actualiza 8 veces y el contador sube; entra Porty, mira el teléfono, habla a cámara y apaga la pantalla |
| 5,6–17,8 s | `phone` | "Si tu cartera se mueve fuerte, Porty te avisa." · "Y te cuenta por qué se movió." · "Y te muestra cómo está repartida tu plata." | Se prende la pantalla bloqueada y llega la notificación (título real de `notify-dispatch`); el toque la convierte en el chat; llega la tarjeta de composición |
| 17,6–22,2 s | `outro` | "Vos seguí con tu día. Porty está atento." · "Descargala gratis. Algunas funciones son de planes pagos." | Porty vuelve, se pone anteojos de sol y asiente |

Letra chica en la imagen (≥ 28 px, dentro de la banda 168–1330 px): "Imagen ilustrativa con datos de ejemplo", Premium, IA y "No es asesoramiento financiero".

## Pendiente antes de publicar
- `porty-compliance`: este reel reemplaza la etiqueta "Cuenta demo" visible desde el segundo 0 (regla del review `docs/legal/reviews/2026-11-03-plan-redes.md` §2) por "Imagen ilustrativa con datos de ejemplo" en la letra chica. Necesita su OK.
- Push funcionando en producción (bloqueante B4): sin eso no se puede decir "te avisa".
- Música desde la biblioteca comercial de TikTok/Instagram al publicar.
