# Ad piloto "Porty está atento" (HyperFrames)

Video 9:16 de 19,5 s a 60 fps hecho con [HyperFrames](https://github.com/heygen-com/hyperframes) (HTML → MP4, open source, Apache-2.0). Sin IA generativa: todo es motion design con la paleta y la tipografía de `DESIGN.md`.

- Salida: `docs/marketing/ads/piezas/2026-11-11/piloto_porty_atento.mp4`
- Renderizar: `npm run render` desde esta carpeta (Node 22+ y FFmpeg; en el entorno cloud, con `PUPPETEER_EXECUTABLE_PATH=/opt/pw-browsers/chromium`).
- Cuadros para revisar: `npm run snapshot`.
- GSAP, fuentes y efectos están en `assets/` para que el render no dependa de la red.
- Hecho siguiendo las skills `hyperframes`, `hyperframes-cli` y `media-use` (`.claude/skills/`).

## Guion (v3, 19,5 s)

| Tiempo | Escena | Qué pasa |
|---|---|---|
| 0–3,4 s | `intro` | "No hace falta mirar el mercado todo el día." ya en el cuadro 0. Porty entra, mira el titular, escucha algo y salta: se convierte en el ícono de la notificación |
| 2,7–14,9 s | `phone` | "Si tu cartera se mueve fuerte, Porty te avisa." · Llega la notificación ("Tu cartera baja 1.8% hoy", título real de `notify-dispatch`) · Toque → la notificación se vuelve el chat · "Y te explica qué pasó, en simple." · "Y te muestra cómo está repartida tu plata." |
| 14,7–19,5 s | `outro` | "Vos seguí con tu día. Porty está atento." · Porty se pone anteojos de sol · "Descargala gratis. Algunas funciones son de planes pagos." |

Efectos: notificación, toque, whoosh, tipeo y pop (`assets/sfx/`, Pixabay Content License, uso comercial permitido). Sin música: se agrega desde la biblioteca comercial de cada red al publicar. Detalle de decisiones y mediciones: `REVIEW.md`.

## Fluidez (cómo se verifica)

- Un solo teléfono para las escenas 2–4: entra, flota todo el tiempo (curva seno) y sale; las pantallas se deslizan adentro en vez de cortar.
- Zoom lento y continuo de cámara durante los 19 s, para que ningún cuadro quede idéntico al anterior.
- Curvas inOut en entradas y salidas, y el titular viejo termina de irse antes de que entre el nuevo.
- Chequeo de cuadros congelados (v3: 1.158 cuadros únicos de 1.170, ningún tramo quieto > 0,08 s):

```bash
ffmpeg -hide_banner -i VIDEO.mp4 -vf "mpdecimate=hi=200:lo=64:frac=0.05,showinfo" -f null - 2>&1 \
  | grep -o 'pts_time:[0-9.]*' | cut -d: -f2 \
  | awk 'NR>1{d=$1-p; if(d>0.04) printf "quieto %.2f→%.2f\n",p,$1} {p=$1} END{print "únicos:",NR}'
```

## Reglas aplicadas (`docs/legal/reviews/2026-11-03-plan-redes.md`)

- "Cuenta demo" en pantalla desde el segundo 0 hasta el final.
- Sin tickers ni rendimientos: la caída es moderada (1,8 %) y la composición va por tipo y sector.
- Disclaimers en la imagen, ≥ 28 px, por encima de los 340 px de abajo: Premium (línea D), IA (línea C) y "No es asesoramiento financiero" (línea A).
- Las pantallas están dibujadas con el diseño de la app, no son capturas: si la app cambia, hay que actualizarlas.

## Pendiente antes de publicar

- Revisión de `porty-compliance` (copy nuevo).
- El push tiene que funcionar en producción (bloqueante B4 del release): sin eso, el ad no puede decir "te avisa".
- Música de la biblioteca comercial de cada red (el render trae solo efectos).
