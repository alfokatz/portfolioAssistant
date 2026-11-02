# Memoria de porty-assistant-dev

- 2026-11-02 Paywall medible: `TurnAbortedException.reason` es un `ChatPaywall(reason, source)` (en assistant_toolset.dart); los sources de cards se arman con `PaywallSource.snake` (camelCase o "+" rompían el assert de `show`). Cambiar solo el string del source no mueve el hash del prompt (verificado).
- Entorno: no hay Flutter en el PATH del contenedor; se baja el SDK estable al scratchpad para correr tests. El hook bloquea `dart format` con flags aunque se listen archivos.
