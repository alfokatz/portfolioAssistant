# REVIEW — piloto "Porty está atento" v3

Hecho siguiendo las skills oficiales `hyperframes`, `hyperframes-cli` y `media-use` (HeyGen), leídas desde la rama `feature/ui_redesign`.

## Decisiones creativas
- Una escena por archivo (`compositions/intro|phone|outro.html`); la raíz solo monta escenas, textos de compliance y audio.
- Transiciones con causa: Porty salta y se convierte en el ícono de la notificación; la notificación crece desde el ícono; al tocarla, se vuelve la pantalla del chat (objeto → mundo); la conversación sigue y llega la tarjeta como mensaje de Porty.
- Entradas variadas: palabra por palabra con desenfoque, de gris a tinta, línea entera desenfocada.
- Porty actúa: anticipación, aplastarse al llegar, mirar el titular y hacia donde llega el teléfono, parpadeo, anteojos que caen, asentir.
- Todo el texto en la banda segura de 9:16 (168–1330 px); el acento de texto es #C27443 (el terracota #D98E5D no llega a 3:1 como texto; se mantiene en el cuerpo de Porty).

## Desvío consciente de la skill
- La skill desaconseja deriva continua de cámara y "respiración" en UI. El pedido explícito fue fluidez total, sin cuadros congelados: hay una deriva vertical lenta del teléfono (30 px en 11 s), luz del fondo de bloqueo que se corre y respiración de Porty (personaje, permitido). Sin eso quedaban pausas de hasta 1,95 s.

## Medido
- `check`: 0 errores. 1 aviso a propósito: la tarjeta de composición está 3 s (`line_unread` pide 6,2 s); es un dato para mirar de un vistazo y el titular lleva el mensaje (`data-hold`).
- Cuadros únicos (mpdecimate): 1.158 de 1.170 a 60 fps; ningún tramo quieto > 0,08 s.
- Audio: sin clipping, true peak −4,8 dBTP, −23 LUFS integrado (solo efectos). Los golpes caen donde la imagen (notificación 3,5 s, toque 6,2 s, tipeo 8,3 s).
- Revisado a ancho de teléfono (360 px): el chat y la tarjeta se leen.

## No verificado
- El sonido se midió, no se escuchó.
- Sin música: no hay catálogo disponible en este entorno (requiere sesión de HeyGen). Se agrega la música desde la biblioteca comercial de TikTok/Instagram al publicar; los efectos están mezclados para quedar por debajo.

## Lo más débil y qué haría con más tiempo
- La escena de composición: 3 s para una tarjeta con 4 números. Con más tiempo, mostraría solo la barra y "Tecnología 46%" y sacaría la leyenda.
- La caída del teléfono y la entrada del cierre se superponen 0,15 s; podría ser un corte más limpio con un "blur swap".
