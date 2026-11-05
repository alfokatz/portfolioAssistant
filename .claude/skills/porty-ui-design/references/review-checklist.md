# Checklist de revisión visual

Pasarla sobre las capturas (claro y oscuro, iPhone SE y Pro) antes de entregar. Cada ítem que falle se corrige y se vuelve a capturar.

## Estructura
- [ ] ¿Cada card se ganó su lugar? ¿Hay alguna card dentro de otra card?
- [ ] Margen lateral 20, aire de 28 entre secciones, nada pegado a los bordes
- [ ] Filas con divisores alineados al texto (no a todo el ancho), alto ≥ 44
- [ ] Jerarquía clara por tipografía: un solo elemento protagonista por pantalla
- [ ] Estado vacío con Porty y próximos pasos; cargando con skeleton de la misma forma; error en voz de Porty

## Color
- [ ] Terracota solo en foco, selección, acciones y Porty; cuento ≤ 2–3 toques de acento por pantalla
- [ ] En oscuro: sin halo ni degradés, círculos de ícono grises (no terracota), nada "flúor", sin negro puro
- [ ] Texto sobre terracota legible (`onAccent`)
- [ ] Verde/rojo solo para ganancia/pérdida o error
- [ ] Contraste AA: texto secundario legible en ambos modos

## Superficie
- [ ] Sin sombras (salvo el glow del input con foco y la sombra tenue del shell de cards del chat en claro)
- [ ] Bordes 1 px `border`, radios del sistema (14 cards/botones, 18 hojas, 6 badges)

## Números y texto
- [ ] Todos los montos y % con tabular figures y el mismo formato
- [ ] Ningún texto cortado, desbordado ni en 3+ líneas donde debía ser 1 (mirar SE)
- [ ] Voseo, minúscula inicial, sin eyebrows en mayúscula, botones que dicen la acción
- [ ] Textos en es y en

## Interacción
- [ ] Sin `AlertDialog`, `SnackBar` ni `CircularProgressIndicator` suelto
- [ ] Animaciones cortas, sin saltos de layout, y con reduce motion respetado
- [ ] Haptics por `PortyHapticsService`
- [ ] Con teclado abierto en SE, el CTA y los campos entran sin scroll

## Errores que ya se cometieron (no repetir)

1. Demasiadas cajas: el total y su gráfico, las metas y las sugerencias terminaron sin card.
2. Acento en exceso en oscuro: diez círculos terracota se leían flúor → tokens `chip`/`onChip`.
3. Degradés y halos en oscuro → `haloStrength 0`, sin bandas de relleno en gráficos.
4. Colores fijos del claro (burbuja blanca, texto ilegible en oscuro).
5. Eyebrows en mayúscula como andamiaje (informe semanal, Ajustes, Metas).
6. Formatos de número mezclados en la misma pantalla.
7. Spinners sueltos y SnackBars → sistema de loaders y `PortyToast`.
8. Respuestas en un solo bloque largo de texto → párrafos y viñetas.
9. Layout que salta al cargar → skeleton de la misma forma, `MotionAwareSize`.
10. Pila de cajas grises iguales para sugerencias (se leían deshabilitadas) → un grupo de filas como Ajustes.
