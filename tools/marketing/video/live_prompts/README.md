# Entradas usadas en Sunra para el video live action

- Planos de contexto: `L1`, `L2` con `bytedance/seedance-2.0-fast/text-to-video`; `L4`, `L5` con `bytedance/seedance-2.0-mini/text-to-video` (la pre-autorización de US$3 por pedido de Fast no entraba en el saldo). 720p, 9:16, 5 s, sin audio.
- Locución: `elevenlabs/multilingual-v2/text-to-speech`, voz Sarah, `language_code: es`.
- Generar: `NODE_USE_ENV_PROXY=1 NODE_EXTRA_CA_CERTS=/root/.ccr/ca-bundle.crt node tools/marketing/video/sunra_gen.mjs <endpoint> <input.json> <salida>` (la key la agrega el proxy del entorno).
- Armar: `node tools/marketing/video/render_overlays.mjs <dir>` y `tools/marketing/video/compose_live.sh <dir> <motion.mp4> <salida.mp4>`.
