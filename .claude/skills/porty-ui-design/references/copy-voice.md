# Voz y textos

## Voz

- **Español rioplatense con voseo**: "Podés", "tenés", "querés", "Elegí", "Tocá", "Contame". Nunca "tienes", "puedes", "agrega".
- **Porty habla en primera persona**, cálido y breve: "Movés una barra y yo ajusto las demás", "No pude importar las posiciones".
- Para un inversor casual: sin jerga de trading (P&L, long, short, bullish) en la UI principal; decir "ganancia", "cuánto subió".
- Nada que suene a recomendación para operar ("Comprá X ya"). Las simulaciones llevan el aviso de "no es asesoramiento" que agrega la app.
- Inglés (`en-US.json`): mismo tono, natural, no traducción literal.

## Forma

- Títulos y títulos de grupo en **minúscula inicial** (sentence case). Nunca MAYÚSCULAS espaciadas como eyebrow de sección ni numeración 01/02/03.
- Botones dicen exactamente qué pasa: "Borrar meta", "Eliminar AAPL", "Conectar Binance". Nunca "Aceptar", "OK", "Confirmar" solo.
- "Cancelar" es la salida secundaria, en texto.
- Errores: qué pasó + qué puede hacer el usuario, en voz de Porty. Debajo del campo o del CTA en `loss`, nunca en un diálogo.
- Encabezados sin dos puntos al final ("Podés empezar por acá").
- Frases cortas; párrafos largos se cortan en párrafos o viñetas.
- Plazos legibles: meses hasta los dos años, después años redondeados ("faltan 16 meses", "faltan 8 años").
- Puntos suspensivos con el carácter `…` ("Buscando {ticker}…").

## Mecánica

- Toda cadena visible en `assets/translations/es-ES.json` **y** `en-US.json`, key `snake_case` con prefijo de feature. Ver skill **porty-architecture**, `references/i18n.md`.
- La marca es **Porty** (nunca "PortfolioAI" / "Portfolio Assistant"; lo controla un test).
- Frases de Porty con números (veredictos de Metas, `PortySays`) se arman en código con datos reales, no las escribe el modelo.
