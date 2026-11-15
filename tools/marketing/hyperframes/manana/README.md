# Tu mañana en dos líneas (HyperFrames)

Video 9:16 de 15,8 s a 60 fps, solo motion design (sin IA generativa). Hecho con la skill `porty-video`.

- Salida: `docs/marketing/social/piezas/2026-11-12/manana.mp4`
- Renderizar: `npm run render` (Node 22+ y FFmpeg; en el entorno cloud, con `PUPPETEER_EXECUTABLE_PATH=/opt/pw-browsers/chromium`). Revisar: `npm run check` y `npm run snapshot`.
- Valor que muestra: Resumen de la mañana y avisos de Porty en la Home (cartera propia, plan gratis): lo importante de lo tuyo sin revisar todo.

## Guion

| Tiempo | Escena | Texto en pantalla | Qué pasa |
|---|---|---|---|
| 0–11,2 s | `morning` | "Son las 8:40. No tenés tiempo de revisar todo." · "Lo que pasó con lo tuyo, con el café en la mano." | Pantalla bloqueada 8:40 y taza de café ilustrada; llega "Porty te marca 2 cosas hoy" (título real; el ticker se reemplazó por "Una de tus posiciones"); al tocarla se vuelve la Home "Hoy te marco 2 cosas" |
| 11,6–15,8 s | `outro` | "Próximamente en App Store y Google Play." · "Vas a poder descargarla gratis." | Porty con anteojos sobre el piso |


**No se publica hasta que el push funcione en producción** (bloqueante B4): el video muestra un aviso.

## Formato (v2, igual al reel "Hola, soy Porty")

- Piso cálido desde y = 1470 px: Porty (o la taza) se para encima y el teléfono queda apoyado detrás, así la mitad de abajo no queda vacía y no hay texto en la zona que tapa la interfaz de la red.
- Sin letra chica suelta: chip "Datos de ejemplo" en cada tarjeta con números (aprobado por `porty-compliance` solo para uso orgánico; si se pauta, vuelve a revisión). Sin notas de "Porty usa IA…" ni de plan (decisión del fundador: están en Términos y Condiciones).
- Cierre común: "Próximamente en App Store y Google Play." · "Vas a poder descargarla gratis." · "Algunas funciones son de planes pagos. No es asesoramiento financiero." (sin lista de espera).
- Pantallas con datos más lentas para que se lean.

## Pendiente antes de publicar
- Música desde la biblioteca comercial de TikTok/Instagram al subirlo (el render trae solo efectos).

Calidad v2: `check` sin errores; 930 de 948 cuadros únicos; ningún tramo quieto > 0,08 s.
