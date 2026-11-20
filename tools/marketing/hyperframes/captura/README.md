# De una captura a tu cartera (HyperFrames)

Video 9:16 de 18,4 s a 60 fps, solo motion design (sin IA generativa). Hecho con la skill `porty-video`.

- Salida: `docs/marketing/social/piezas/2026-11-12/captura.mp4`
- Renderizar: `npm run render` (Node 22+ y FFmpeg; en el entorno cloud, con `PUPPETEER_EXECUTABLE_PATH=/opt/pw-browsers/chromium`). Revisar: `npm run check` y `npm run snapshot`.
- Valor que muestra: Carga por captura (plan gratis, usa 1 consulta): si tu bróker no está en la lista, una captura alcanza para traer la cartera.

## Guion

| Tiempo | Escena | Texto en pantalla | Qué pasa |
|---|---|---|---|
| 0–4,45 s | `shot` | "¿Tu bróker no está en la lista? Sacale una captura." | App de inversiones genérica ("Mis posiciones"); destello de captura, la miniatura vuela hasta Porty y Porty entra al teléfono con ella |
| 4,4–12,4 s | `phone` | "Y tu cartera queda cargada en Porty." | Textos reales de la app: "Traé tu cartera · Una captura de pantalla… Uso 1 consulta" → "Leyendo tu captura…" → "En tu captura · 6 de 6 listas" → Guardar → "Listo, sumé 6 posiciones" → "Miré tu cartera" |
| 14,2–18,4 s | `outro` | "Próximamente en App Store y Google Play." · "Vas a poder descargarla gratis." | Porty con anteojos sobre el piso |


Texto para el caption de la publicación (pedido de compliance): "Tapá tu nombre y tu número de cuenta antes de subirla."

## Formato (v2, igual al reel "Hola, soy Porty")

- Piso cálido desde y = 1470 px: Porty (o la taza) se para encima y el teléfono queda apoyado detrás, así la mitad de abajo no queda vacía y no hay texto en la zona que tapa la interfaz de la red.
- Sin letra chica suelta: chip "Datos de ejemplo" en cada tarjeta con números (aprobado por `porty-compliance` solo para uso orgánico; si se pauta, vuelve a revisión). Sin notas de "Porty usa IA…" ni de plan (decisión del fundador: están en Términos y Condiciones).
- Cierre común: "Próximamente en App Store y Google Play." · "Vas a poder descargarla gratis." · "Algunas funciones son de planes pagos. No es asesoramiento financiero." (sin lista de espera).
- Pantallas con datos más lentas para que se lean.

## Pendiente antes de publicar
- Música desde la biblioteca comercial de TikTok/Instagram al subirlo (el render trae solo efectos).

Calidad v2: `check` sin errores; 1.098 de 1.104 cuadros únicos; ningún tramo quieto > 0,08 s.
