# Ad piloto "Porty está atento" (HyperFrames)

Video 9:16 de 19 s a 60 fps hecho con [HyperFrames](https://github.com/heygen-com/hyperframes) (HTML → MP4, open source, Apache-2.0). Sin IA generativa: todo es motion design con la paleta y la tipografía de `DESIGN.md`.

- Salida: `docs/marketing/ads/piezas/2026-11-11/piloto_porty_atento.mp4`
- Renderizar: `npm run render` desde esta carpeta (Node 22+ y FFmpeg; en el entorno cloud, con `PUPPETEER_EXECUTABLE_PATH=/opt/pw-browsers/chromium`).
- Cuadros para revisar: `npx --yes hyperframes@0.9.33 snapshot --at 2.5,6,11,14.8,18.5`.
- GSAP y las fuentes están copiados en `vendor/` y `fonts/` para que el render no dependa de la red.

## Guion

| Tiempo | Escena | Texto |
|---|---|---|
| 0–3,2 s | Gancho, entra Porty | "No hace falta mirar el mercado todo el día." |
| 3,2–8 s | Pantalla bloqueada, llega la notificación | "Si tu cartera se mueve fuerte, Porty te avisa." · Notificación: "Tu cartera baja 1.8% hoy" (título real de `notify-dispatch`, tipo `portfolio_move`) |
| 8–12,6 s | Chat | "Y te explica qué pasó, en simple." |
| 12,6–15,6 s | Composición de la cartera | "Y te muestra cómo está repartida tu plata." |
| 15,6–19 s | Cierre, Porty con anteojos de sol | "Vos seguí con tu día. Porty está atento." · "Descargala gratis. Algunas funciones son de planes pagos." |

## Fluidez (cómo se verifica)

- Un solo teléfono para las escenas 2–4: entra, flota todo el tiempo (curva seno) y sale; las pantallas se deslizan adentro en vez de cortar.
- Zoom lento y continuo de cámara durante los 19 s, para que ningún cuadro quede idéntico al anterior.
- Curvas inOut en entradas y salidas, y el titular viejo termina de irse antes de que entre el nuevo.
- Chequeo de cuadros congelados (debería decir ~1.130 cuadros únicos de 1.140, solo los primeros 0,12 s quietos):

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
- Música de la biblioteca comercial de cada red (el render no tiene audio).
