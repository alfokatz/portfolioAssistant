# REVIEW — reel "Porty está atento"

## Decisiones
- Formato de red social: gancho con humor calmo (el contador de veces que mirás la cartera) en el cuadro 0, Porty como personaje que resuelve, producto real y cierre con CTA.
- "en simple" se reemplazó por "Y te cuenta por qué se movió." (pedido del usuario).
- Continuidad: el teléfono de `hook` y `phone` tiene la misma geometría y la misma deriva (empalma en y = 14 px); la pantalla se apaga en una escena y se prende en la otra.
- Sin etiqueta "Cuenta demo": la aclaración va en la letra chica ("Imagen ilustrativa con datos de ejemplo"). Pendiente de compliance.

## Medido
- `check`: 0 errores. 5 avisos `overlapping_gsap_tweens` en `#hk-app`/`#hk-spin`: falsos positivos (el análisis estático no resuelve los tiempos del bucle de 8 actualizaciones; cada una empieza 0,34 s después de la anterior).
- Cuadros únicos: 1.321 de 1.332 a 60 fps; ningún tramo quieto > 0,08 s.
- Audio: sin clipping, true peak −4,8 dBTP, −24 LUFS (solo efectos; la música se suma en la red).

## No verificado
- El sonido se midió, no se escuchó.
- Sin música (no hay sesión de HeyGen en el entorno).

## Lo más débil
- El paso de pantalla apagada a pantalla bloqueada (5,6–5,9 s) es el momento con menos información; podría llevar un "Más tarde…" o la hora cambiando.
