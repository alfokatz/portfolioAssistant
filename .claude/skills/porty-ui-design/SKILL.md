---
name: porty-ui-design
description: Lineamientos de diseño UX/UI de Porty ("The Quiet Ledger") aplicados al código Flutter - tokens de color, tipografía, radios y espacios del tema, widgets compartidos que hay que reusar (ConfirmSheet, PortyToast, PortySays, loaders), kit de las cards del chat, voz de los textos y checklist de revisión visual. Usar siempre que se cree o modifique una pantalla, widget, card del chat, hoja, estado vacío, loader, animación o texto visible de la app, o al revisar un diseño o una captura.
---

# Diseño de Porty en código

**Fuente de verdad del diseño:** `DESIGN.md` (sistema visual, reglas con nombre, componentes por pantalla) y `PRODUCT.md` (usuario, personalidad, principios). Antes de diseñar algo, leer la sección de `DESIGN.md` del componente o pantalla que vas a tocar. Esta skill dice **cómo se hace en código** y qué ya existe; si algo choca con `DESIGN.md`, gana `DESIGN.md`.

## El carácter en una línea

Inversor retail casual, no trader. **Premium silencioso**: cuaderno financiero bien editado, mucho aire, cifras que mandan, un solo acento terracota, superficies planas. Nada de fintech navy+neón, AI slop, casino tipo Robinhood ni scaffolding SaaS.

## Las 12 reglas que más se rompen

1. **Colores solo por token**: `context.customColors.<token>` (`theme_extension.dart`). Nunca hex, `Colors.white/black` ni `PortfolioColors` directo en un widget. Dentro del catálogo del chat: `QaColors.*`.
2. **Claro y oscuro desde el primer intento.** Lo que cambia en oscuro es un token (`haloStrength`, `glowScale`, `chip/onChip`, `inset`, `onAccent`), no un `if (dark)`. Sobre un relleno terracota, texto `onAccent`.
3. **Una sola acento**: terracota (`accentBlue`/`accentWarm`, nombre histórico, no es azul) solo para foco, selección, acciones (FAB, enviar, Editar, switches) y Porty. Nunca de fondo grande. CTA primario = tinta (`textPrimary`) con texto `surfaceCard`.
4. **Plano**: sin sombras en reposo, `elevation: 0`. Jerarquía con superficie más clara o borde 1px `border`. Única sombra permitida: glow del input con foco.
5. **"Earn every card"**: preferir filas editoriales sobre el fondo con divisores alineados al texto. Nunca card dentro de card (adentro, `inset`). El total, su gráfico y las listas van sin card.
6. **Números**: tabular figures en todo monto, porcentaje y precio (`fontFeatures: const [FontFeature.tabularFigures()]`). Formato con `AppNumberFormat` (o `QaFormat` en el chat); nunca `toStringAsFixed` armado a mano.
7. **Tipografía**: solo Plus Jakarta Sans vía `Theme.of(context).textTheme` (o `QaText`). Variación por peso y tamaño, no por familia. Sin `GoogleFonts`.
8. **Medidas por constante**: `AppDimens` (`pageHorizontal 20`, `sectionGap 28`, `cardPadding 18`, `radiusLg 14`, `radiusXl 18`, `touchTarget 44`). Nunca el bloque "Legacy" de `AppDimens`.
9. **Sin diálogos ni snackbars**: confirmar con `ConfirmSheet.show`, avisar con `alertProvider` → `PortyToast`, errores de formulario en texto `loss` debajo del campo. El botón dice exactamente lo que pasa ("Borrar meta"), nunca "Aceptar"/"OK".
10. **Loaders**: skeleton si conocés el layout, `PortyLoader` si no, `ButtonSpinner` en botones; siempre con la regla 300/400 ms (`LoadingSwitcher`). Ningún `CircularProgressIndicator` suelto.
11. **Movimiento**: 150–250 ms, `Curves.easeOutCubic`; respetar `MediaQuery.disableAnimationsOf(context)`; `MotionAwareSize` en vez de `AnimatedSize`. Haptics solo por `PortyHapticsService`, nunca `HapticFeedback` directo.
12. **Textos**: español rioplatense con voseo, Porty en primera persona, sin jerga de trading; títulos en minúscula inicial, **sin eyebrows en mayúsculas** ni numeración 01/02/03; claves en `es-ES.json` y `en-US.json`.

## Flujo de trabajo

```
- [ ] 1. Leer la sección de DESIGN.md de lo que vas a tocar (y PRODUCT.md si es pantalla nueva)
- [ ] 2. Buscar si ya existe el widget: references/components.md
- [ ] 3. Implementar con tokens: references/tokens-in-code.md
         (cards del chat: references/genui-kit.md)
- [ ] 4. Estados: vacío (Porty explica + ideas, nunca caja vacía), cargando (skeleton con la misma forma), error, deshabilitado
- [ ] 5. Textos: references/copy-voice.md
- [ ] 6. Generar screenshots claro/oscuro × SE/Pro y MIRARLAS (skill porty-testing, references/screenshots.md)
- [ ] 7. Pasar references/review-checklist.md sobre las capturas; corregir y volver al paso 6 hasta que pase
```

El paso 6–7 no es opcional para UI visible: es lo que evita el ida y vuelta con el usuario.

Si la pantalla necesita un patrón que `DESIGN.md` no cubre, proponerlo siguiendo las reglas con nombre de `DESIGN.md` y, al terminar, ofrecer documentarlo ahí.

## Referencias

- [references/tokens-in-code.md](references/tokens-in-code.md): colores, tipografía, dimensiones, tema, formato de números.
- [references/components.md](references/components.md): widgets compartidos a reusar y patrones de pantalla.
- [references/loaders-and-motion.md](references/loaders-and-motion.md): loaders, animaciones, haptics, reduce motion.
- [references/genui-kit.md](references/genui-kit.md): kit de las cards del chat (`QaText`, `QaColors`, `QaSpace`, primitivas).
- [references/copy-voice.md](references/copy-voice.md): voz, tono y reglas de texto.
- [references/review-checklist.md](references/review-checklist.md): checklist de revisión visual y errores históricos.
