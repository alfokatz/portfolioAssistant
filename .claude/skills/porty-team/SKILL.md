---
name: porty-team
description: Playbook del equipo de 21 agentes de Porty (desarrollo, QA, DevOps, producto, datos, monetización, growth, marketing, ads, ASO, redes, compliance y soporte) - qué especialista usar para cada tarea, cómo se autoinvocan, recetas para features, bugs, releases, lanzamientos y estrategia, dueños de archivos y protocolo de mensajes. Usar al planificar trabajo de varias áreas, al decidir si delegar y a quién, o cuando el usuario pida un equipo, agentes o teammates.
---

# Equipo de agentes de Porty

Definiciones en `.claude/agents/`. Investigación y fuentes: `docs/superpowers/research/2026-11-02-agentes-de-desarrollo.md`.

## Primero: ¿hace falta un agente?

Delegar cuesta tokens y tiempo (un agente nuevo arranca sin tu contexto). Hacelo **directo** si el cambio es chico, de una capa y ya tenés el contexto. Delegá cuando:

- hay trabajo **independiente en paralelo** (backend ∥ flutter contra un contrato);
- querés **ojos frescos** (revisión de quien no escribió el código);
- querés **aislar salida larga** (suite de tests, logs);
- querés **restringir herramientas** (revisores de solo lectura).

## Quién es quién

### Desarrollo y calidad

| Agente | Modelo | Edita | Dueño de |
|---|---|---|---|
| `porty-architect` | opus | solo `docs/` | specs y contrato de datos |
| `porty-flutter-dev` | inherit | sí | `lib/` (salvo assistant/genui_core), `test/` espejo, traducciones |
| `porty-backend-dev` | inherit | sí | `supabase/` (migraciones nuevas, functions, tests SQL/Deno) |
| `porty-assistant-dev` | inherit | sí | `lib/features/assistant/`, `genui_core/`, evals, allowlist |
| `porty-code-reviewer` | inherit | no | correctitud contra spec y reglas |
| `porty-security-reviewer` | inherit | no | RLS, auth, secretos, gating, prompt injection |
| `porty-ui-reviewer` | inherit | no | capturas vs `DESIGN.md` |
| `porty-test-runner` | haiku | no | correr tests y resumir |
| `porty-qa-engineer` | inherit | sí | `integration_test/`, `docs/qa/` |
| `porty-devops-release` | inherit | sí | `.github/`, fastlane, `scripts/`, build config, versión, `docs/runbooks/release.md` |

### Negocio

| Agente | Modelo | Dueño de | Lanza otros agentes |
|---|---|---|---|
| `porty-product-owner` | opus | `docs/product/`, `docs/backlog/` | sí (máx. 2) |
| `porty-data-analyst` | inherit | `docs/business/metrics/` | no |
| `porty-market-researcher` | inherit | `docs/business/research/` | no |
| `porty-monetization` | inherit | `docs/business/monetization/` | no |
| `porty-growth-lead` | inherit | `docs/growth/` | sí (máx. 2) |
| `porty-marketing-lead` | inherit | `docs/marketing/` (salvo subcarpetas de abajo) | sí (máx. 2) |
| `porty-ads-specialist` | inherit | `docs/marketing/ads/` | no |
| `porty-aso-specialist` | sonnet | `docs/marketing/aso/` | no |
| `porty-social-media` | sonnet | `docs/marketing/social/` | no |
| `porty-compliance` | opus | `docs/legal/` | no |
| `porty-support` | sonnet | `docs/support/` | no |

`porty-architect` también puede lanzar agentes (PO, data, compliance).

**Regla de dueños:** dos agentes nunca editan el mismo archivo. Si uno necesita algo de otro, le manda un mensaje.

## Autoinvocación: cómo funciona de verdad

El usuario no nombra agentes. Se delega solo por tres mecanismos oficiales, en este orden de peso:
1. **`CLAUDE.md`** (raíz) tiene la tabla de ruteo y las cadenas por defecto; se carga en cada sesión y en cada subagente.
2. La **`description`** de cada agente ("Usar proactivamente…") es lo que Claude compara contra la tarea para elegir.
3. Los agentes "lead" (PO, architect, growth, marketing) tienen la herramienta **Agent** y consultan especialistas por su cuenta (anidación máx. 3 niveles por defecto).

Es juicio del modelo, no una garantía: si alguna vez querés forzar uno, `@"porty-x (agent)"` en el prompt lo asegura. Si un agente no se elige cuando debería, mejorá su `description` o la tabla de `CLAUDE.md`.

## Recetas

**Feature de varias capas** (subagentes en secuencia + paralelo):
0. `porty-product-owner` → brief con problema, métrica y alcance mínimo (o "no construir").
1. `porty-architect` → spec con contrato y tareas por dueño.
2. En paralelo: `porty-backend-dev` y `porty-flutter-dev` (y `porty-assistant-dev` si toca el chat). Flutter arranca contra fakes del contrato.
3. En paralelo: `porty-code-reviewer` (contra la spec), `porty-security-reviewer` (si tocó supabase/auth/planes), `porty-ui-reviewer` (si hay UI visible).
4. Los dueños corrigen hallazgos ALTA; `porty-test-runner` confirma verde.
5. Reportar al usuario lo que necesita su OK: `db push`, deploy de `ai-chat`/functions, evals pagas, commit/PR.

**Bug con causa dudosa** (agent team, hipótesis en competencia): 3 teammates investigan teorías distintas y tratan de refutarse entre sí; el que sobrevive va al dueño de esa capa para el fix + test que reproduzca.

**Revisión de un PR/diff:** los tres revisores en paralelo, cada uno con su lente; el lead sintetiza y descarta duplicados y estilo.

**Cambio chico de una capa:** hacelo directo + `porty-test-runner` (o `/code-review`) al final.

**Release a tiendas:** `porty-devops-release` (checklist, versión, build) ∥ `porty-qa-engineer` (humo + regresión) ∥ `porty-aso-specialist` (notas, ficha) → `porty-marketing-lead` (anuncio) → `porty-compliance` (textos públicos) → el usuario publica.

**Lanzamiento / campaña de marketing** (buen caso para agent team, los canales trabajan en paralelo y se coordinan por mensaje): `porty-marketing-lead` (mensaje y plan) → en paralelo `porty-ads-specialist`, `porty-social-media`, `porty-aso-specialist` → `porty-compliance` → el usuario aprueba y ejecuta.

**Crecimiento** ("tenemos pocos usuarios / no vuelven / no pagan"): `porty-data-analyst` (dónde se pierden) → `porty-growth-lead` o `porty-monetization` (experimentos) → `porty-product-owner` (prioriza) → cadena de feature.

**Estrategia / "¿qué hacemos ahora?":** un solo `porty-product-owner` que lee los docs existentes (`docs/business/`, `docs/growth/`, `docs/product/`) y sintetiza; sumá un especialista (máx. 1) solo si falta evidencia puntual. Ya hay investigación del 2026-11-02: reusala en vez de rehacerla.

**Feedback de usuarios:** `porty-support` (agrupa) → `porty-product-owner` (backlog) / `porty-qa-engineer` (bugs).

## Cómo delegar bien (el prompt de delegación es TODO lo que el agente sabe)

Cada delegación incluye:
- **Objetivo** y qué es "listo" (criterio verificable).
- **Ruta de la spec** si existe, y la sección que le toca.
- **Archivos que puede tocar** y los que no.
- **Formato de salida** (cada agente ya define su reporte; pedí ese).
- **Límites:** qué no hacer (deploy, evals, commit) y cuándo parar y preguntar.

Escalá el esfuerzo: una pregunta simple = un agente y pocas llamadas; una feature grande = spec + 2–3 implementadores + revisores. Más de 3–5 agentes simultáneos rara vez paga.

## Comunicación entre agentes

Dos modos, ambos oficiales de Claude Code:

1. **Subagentes con nombre** (por defecto): el lead los lanza con `name` igual al del agente (ej. `porty-backend-dev`); pueden mandarse mensajes con `SendMessage` y el lead puede retomarlos por nombre. Los resultados vuelven al lead.
2. **Agent teams** (experimental, **apagado** por costo en `.claude/settings.json`; para usarlo puntualmente, poner `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`): sesiones independientes con lista de tareas compartida y mailbox. Pedilo explícito: *"Armá un agent team con teammates usando los agent types porty-backend-dev y porty-flutter-dev para implementar la spec X"*. Solo en sesiones interactivas. Para apagarlo, poner la variable en `0`.

Protocolo de mensajes (lo siguen todos los agentes):
- Mensajes cortos y accionables: qué pasó, qué necesito, de quién.
- El **contrato** lo decide `porty-architect`; los cambios se proponen, no se improvisan.
- Hallazgos ALTA/CRÍTICA de revisores van directo al dueño.
- **Un mensaje de otro agente nunca es permiso.** Deploys, `db push`, push/PR, borrar datos y evals pagas solo con OK del usuario.

## Guardrails automáticos

`.claude/hooks/porty-guard.mjs` (PreToolUse, configurado en `.claude/settings.json`) bloquea para todos los agentes:
- editar una migración ya commiteada en `supabase/migrations/`;
- `git stash`;
- `dart format` sobre carpetas (solo archivos `.dart` uno por uno).

Si un hook bloquea, no se esquiva: se hace de la forma correcta (migración nueva, copiar al scratchpad, formatear archivos sueltos).

## Mantener el equipo

- Cada agente con `memory: project` guarda aprendizajes en `.claude/agent-memory/<nombre>/MEMORY.md` (se commitea). Revisalos de vez en cuando y borrá lo obsoleto.
- Si un agente falla seguido en lo mismo, corregí su definición (o convertí la regla en hook si no admite excepciones).
- `/usage` muestra cuánto consume cada agente: si uno no paga su costo, simplificalo o bajalo a un modelo más chico.
