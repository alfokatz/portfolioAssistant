# Tu mañana en dos líneas (HyperFrames)

Video 9:16 de 15,6 s a 60 fps, solo motion design (sin IA generativa). Hecho con la skill `porty-video`.

- Salida: `docs/marketing/social/piezas/2026-11-12/manana.mp4`
- Renderizar: `npm run render` (Node 22+ y FFmpeg; en el entorno cloud, con `PUPPETEER_EXECUTABLE_PATH=/opt/pw-browsers/chromium`). Revisar: `npm run check` y `npm run snapshot`.
- Valor que muestra: Resumen de la mañana y avisos de Porty en la Home (cartera propia, plan gratis): lo importante de lo tuyo sin revisar todo.

## Guion

| Tiempo | Escena | Texto en pantalla | Qué pasa |
|---|---|---|---|
| 0–11,2 s | `morning` | "Son las 8:40. No tenés tiempo de revisar todo." · "Lo que pasó con lo tuyo, con el café en la mano." | Pantalla bloqueada 8:40 y taza de café ilustrada; llega "Porty te marca 2 cosas hoy" (título real; el ticker se reemplazó por "Una de tus posiciones"); al tocarla se vuelve la Home "Hoy te marco 2 cosas" |
| 11–15,6 s | `outro` | "Seguí con tu día: Porty te avisa si se mueve fuerte." · "Descargala gratis. Algunas funciones son de planes pagos." | Porty con anteojos |

Letra chica (regla de compliance del 2026-11-12): "Imagen ilustrativa con datos de ejemplo." fija desde el segundo 0 y, en los últimos 3 s, "Imagen ilustrativa con datos de ejemplo. No es asesoramiento financiero."

**No se publica hasta que el push funcione en producción** (bloqueante B4): el video muestra un aviso.

## Pendiente antes de publicar
- Música desde la biblioteca comercial de TikTok/Instagram al subirlo (el render trae solo efectos).
- Revisión final de `porty-compliance` sobre el video renderizado (el copy ya fue revisado el 2026-11-12).
