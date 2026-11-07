# Video live action con IA — "Porty en tu día" (borrador)

Objetivo: presentar Porty con escenas cotidianas reales (generadas con IA de video) + la UI real de la app compuesta en la pantalla del teléfono. 9:16, 20–24 s, voz en off con IA (guion abajo).

Herramienta: Sunra API (`SUNRA_API_KEY`). Modelos candidatos: Kling 3.0 / Veo 3.1 (image-to-video, 9:16, 1080p) para planos; ElevenLabs (vía Sunra) para la voz. Composición final con ffmpeg sobre las escenas generadas + el motion design ya hecho (`porty_ad.html`) para los planos de pantalla.

## Reglas (compliance + marca)

- La IA **no** genera la UI: los planos de pantalla usan capturas reales (screenshot tests, cuenta demo) compuestas o el motion design existente.
- Sin testimonios en primera persona de personas generadas, sin promesas de ganancia, sin dinero/billetes/gráficos de trading.
- Personas de espaldas, de perfil o manos; caras no protagonistas. Estética calma, luz natural cálida, paleta canvas/terracota (`DESIGN.md`), nada de neón.
- Etiquetar el video como contenido generado con IA en Instagram y TikTok; voz sintética declarada.

## Planos

| # | Duración | Plano (generado con IA) | Pantalla / texto | Locución |
|---|---|---|---|---|
| 1 | 0–3 s | Mañana, cocina luminosa: mano sostiene un café, el teléfono apoyado en la mesa se ilumina. Cámara lenta, poca profundidad de campo. | Titular: "¿Cómo viene tu plata?" | ¿Tu plata está repartida en varios lados? |
| 2 | 3–6 s | Colectivo / tren por la ciudad, persona de perfil mirando el teléfono, luz de ventana que pasa. | Sobre la pantalla: chips "Bróker", "Exchange", "Planilla" que convergen | Juntala en Porty. |
| 3 | 6–11 s | Plano cerrado del teléfono en la mano (el modelo genera mano + teléfono con pantalla verde/neutral para reemplazar). | Composición: pantalla real con la card de cartera (SPY, NVDA, AAPL con logos) | La entendés de un vistazo… |
| 4 | 11–15 s | Sábado, sillón, luz de tarde: persona relajada leyendo el teléfono, sonríe leve. | Composición: diagnóstico / informe semanal real | …y Porty te cuenta lo que vio, en simple. |
| 5 | 15–19 s | Plano detalle: pulgar tipeando en el teléfono. | Composición: chat real "¿Cómo me fue esta semana?" → informe | Le preguntás lo que quieras entender de tu cartera. |
| 6 | 19–23 s | Cierre del motion design (avatar `porty_idle`, "Porty", "Descargala gratis") sobre el halo terracota. | — | Porty. Descargala gratis. |

## Pasos en la sesión nueva

1. Verificar saldo y modelos de la API; estimar costo de los 5 planos (4–5 s c/u) y de la voz, y confirmarlo con el usuario antes de generar.
2. Generar primero un plano de prueba (plano 3, el más difícil por la mano y el teléfono) para validar estilo y reemplazo de pantalla.
3. Generar el resto, la voz, componer las pantallas reales (tracking simple / pantalla en verde) y exportar 1080x1920.
4. Revisión de `porty-compliance` antes de publicar (personas generadas, etiqueta de IA).
