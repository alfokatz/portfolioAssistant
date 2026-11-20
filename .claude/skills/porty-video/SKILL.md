---
name: porty-video
description: Producción de videos y creatividades de Porty con HyperFrames - manual de mensajes, reglas de compliance para el copy, composición (teléfono, notificación, chat, Porty animado), planos de vida real con IA en Sunra (método imagen → video para no gastar créditos de más), grabaciones reales de la app, efectos de sonido, y control de calidad (60 fps sin cuadros congelados, zona segura 9:16, lectura a 360 px). Usar siempre que haya que producir, renderizar, editar o corregir un video, reel, anuncio en video o variante de una pieza, o escribir prompts de Sunra para Porty.
---


# Producción de videos de Porty

El trabajo empieza cuando el qué ya está decidido: con un brief aprobado se entrega un video que se puede subir tal cual, que se ve 100 % fluido y que muestra el valor real de Porty sin prometer de más. Esta skill la usa quien produzca (la sesión principal o Claude Code en la compu del fundador); no hace falta delegar en un agente.

## Manual (leelo antes de cada video)

- `docs/marketing/ads/prompt-claude-code-videos.md` §2–§6: mensajes, reglas de texto, cómo se hace con HyperFrames, fluidez y reglas del proyecto. Es la fuente de verdad técnica; no la contradigas.
- Skills `hyperframes`, `hyperframes-cli` y `media-use` en `.claude/skills/`: contrato, proceso de trabajo (check → snapshot --review → REVIEW.md → render) y efectos de sonido.
- Referencias: `tools/marketing/hyperframes/reel-atento/` (estructura, teléfono, notificación, chat, Porty, mezcla de sonido) y `piloto-atento/REVIEW.md` (qué funcionó y qué no).
- Briefs con planos de IA: `docs/marketing/ads/2026-11-12-briefs-videos-ia.md` (filtro de valor, método imagen → video, bloque de estilo, prompts).

## Dónde va cada cosa

- Proyectos de video: `tools/marketing/hyperframes/<nombre>/` (uno por video, con `README.md` y `REVIEW.md`).
- Salidas: los `.mp4` en `docs/marketing/ads/piezas/<fecha>/` y `docs/marketing/social/piezas/<fecha>/`. Los `.md` de esas carpetas siguen siendo de ads-specialist y social-media.
- Planos generados y prompts usados: `tools/marketing/hyperframes/<nombre>/assets/` y `prompts.md` del proyecto.

## Cómo se trabaja

1. **Sin brief aprobado no producís.** El brief tiene que decir: dolor, función real de Porty (con su plan), prueba en pantalla, gancho, guion por segundos y textos. Si falta algo, se le pide al usuario o al agente dueño del brief; no se inventa.
2. **Texto:** usás el copy del brief tal cual. Si un texto rompe las reglas del manual §3 (por ejemplo "recomendaciones", "en simple", tickers, "gratis" a secas), lo marcás y proponés alternativa; no lo publicás vos.
3. **IA solo donde el brief la justifica** (pregunta "¿qué aporta la IA que no logre la animación?"). Método para no repetir: 3 imágenes de cuadro inicial (Nano Banana Pro) → se elige una → un video image-to-video (Kling 3.0 standard) → misma persona con la imagen elegida como referencia. La IA nunca dibuja la app.
4. **Créditos:** antes de cualquier generación paga, `estimate_cost` y `get_balance`. Solo se genera con aprobación explícita del usuario para ese gasto (con tope); si no, se le muestra la estimación y los prompts listos y se espera. Nunca HeyGen ni otros servicios pagos. Telemetría de HyperFrames apagada; no corras el "usage beacon".
5. **Grabaciones reales de la app:** pedilas al usuario con la lista de tomas de `docs/marketing/social/2026-11-03-plan-lanzamiento-ig-tiktok.md` §4; cuenta demo, ±15 % máximo, sin tickers destacados, barra de estado limpia, 60 fps. Recortás los tramos donde la app queda quieta.
6. **Control de calidad antes de entregar (obligatorio):** `check` sin errores; `snapshot --review` revisado (incluida la hoja a 360 px); medición de fluidez con el comando del manual §5 (≥ 98 % de cuadros únicos, ningún tramo quieto > 0,1 s salvo el cuadro 0); `hyperframes audio` sin clipping. Texto en la banda 168–1330 px, ≥ 28 px, acento de texto #C27443.
7. **Variantes para pauta:** cuando el brief pida test, producís las variantes que cambian una sola cosa (gancho, duración 6–9 s vs 15–20 s, o mensaje) y las nombrás `<pieza>_v<letra>_<qué-cambia>.mp4`.

## Límites

- No publicás en redes, no subís a cuentas de anuncios, no gastás créditos sin aprobación explícita del usuario, no hacés push ni PR.
- No tocás código de la app (`lib/`, `supabase/`) ni los `.md` de estrategia de otros agentes.
- Todo copy nuevo o cambiado pasa por `porty-compliance` antes de que el usuario lo publique: lo marcás como pendiente en el reporte.

## Entrega (resumen para el usuario)

```
Video: <ruta .mp4> (<duración>, 60 fps)
Guion: <tiempo · escena · texto> por línea
Calidad: check <ok/avisos>, cuadros únicos <n de m>, audio <true peak / LUFS>
IA: <planos generados, créditos gastados / estimados, o "sin IA">
Pendiente: <compliance / push en producción / música / grabaciones>
```
