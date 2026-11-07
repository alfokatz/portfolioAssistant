# Agentes de desarrollo para Porty: qué recomienda Anthropic y cómo lo aplicamos

Fecha: 2026-11-02. Implementación: `.claude/agents/`, `.claude/skills/porty-team/`, `.claude/hooks/porty-guard.mjs`, `.claude/settings.json`.

## Lo que dicen las fuentes oficiales

### 1. Empezar simple y agregar agentes solo cuando pagan
*Building effective agents* (Anthropic): la mayoría de los éxitos en producción usan patrones simples y componibles, no frameworks complejos. Los cinco patrones son: **prompt chaining**, **routing**, **parallelization** (secciones o votación), **orchestrator-workers** y **evaluator-optimizer**. Los tres principios son simplicidad, transparencia (que se vea el plan) y una interfaz agente-computadora (herramientas) bien diseñada.

### 2. Orchestrator-worker con delegación precisa
*How we built our multi-agent research system* (Anthropic Engineering): un agente líder planifica, lanza subagentes en paralelo con contexto propio y sintetiza. Las lecciones son:
- Cada delegación necesita **objetivo, formato de salida, herramientas o fuentes y límites claros**. Las instrucciones vagas causan trabajo duplicado y huecos.
- **Escalar el esfuerzo** al pedido. Los agentes tienden a sobreinvertir en lo simple, así que las reglas tienen que estar explícitas.
- La descripción de cada herramienta importa tanto como una UI.
- Multi-agente consume **muchos más tokens**. Paga en tareas valiosas y paralelizables. En código hay menos partes independientes, así que se usa con criterio.
- Para evaluar, empezar con pocos casos reales, usar un juez con rúbrica y mirar el estado final, no el camino.

### 3. Subagentes de Claude Code
*Custom subagents* (docs de Claude Code):
- Archivo Markdown con frontmatter en `.claude/agents/`, versionado con el repo. El cuerpo es el system prompt. El agente **no** recibe la conversación del lead: el prompt de delegación es todo lo que sabe.
- La `description` decide cuándo se delega ("use proactively" ayuda a que se delegue sin pedirlo). Hay que mantenerla corta.
- **Herramientas mínimas**: los revisores no tienen Edit ni Write. Esa restricción la aplica el harness, no depende del prompt.
- **Modelo por tarea**: Haiku para trabajos simples o de mucha lectura.
- `skills:` precarga skills del proyecto, `memory: project` da memoria persistente versionada, `isolation: worktree` trabaja en una copia aparte, y también existen `hooks`, `effort`, `color` y `maxTurns`.
- Usarlos para **aislar salida voluminosa** (tests, logs), tener **ojos frescos** y restringir permisos. Cuidado con muchos en paralelo: todos devuelven resultados al contexto principal.
- Los subagentes con nombre se pueden mandar mensajes con `SendMessage`, y el lead los retoma por nombre.

### 4. Agent teams (experimental)
*Orchestrate teams of Claude Code sessions*:
- Un lead y varios teammates, cada uno una sesión completa, con **lista de tareas compartida** y **mailbox**: se mandan mensajes directamente entre ellos.
- Se activan con `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` y solo funcionan en sesiones interactivas.
- Una definición de `.claude/agents/` se reusa como teammate ("spawn a teammate using the X agent type").
- Mejores casos: investigación y revisión en paralelo, módulos nuevos con dueños separados, **debugging con hipótesis en competencia** (se refutan entre sí) y cambios que cruzan capas.
- Hay que arrancar con **3–5 teammates** y 5–6 tareas por teammate, **evitar que dos editen el mismo archivo** y monitorear.
- Los hooks `TeammateIdle`, `TaskCreated` y `TaskCompleted` sirven como quality gates.
- Un mensaje de otro agente **nunca** aprueba un permiso.

### 5. Best practices de Claude Code
- **Writer / reviewer**: el código lo revisa alguien que no lo escribió (`/code-review` o un subagente revisor de solo lectura), contra la spec y **salteando estilo**. Un revisor al que le piden problemas siempre encuentra algo.
- Escribir la spec primero y construir después, en un contexto limpio.
- **Lo que no admite excepciones va en hooks o deny rules**, no en CLAUDE.md: el prompt es una guía y el hook es una garantía. Conviene mantener pocas reglas forzadas.
- Un subagente no es más inteligente: aporta paralelismo, ojos frescos o restricciones. Hay que medir con `/usage` si cada uno paga su costo.

### Cómo trabajan hoy los equipos de Anthropic (fuentes secundarias)
No encontré un relato de primera mano reciente sobre el uso interno de subagentes y teams. Las coberturas de terceros coinciden en lo que dicen las docs: subagentes para trabajos acotados que reportan a un decisor central, y teams cuando los agentes tienen que compartir hallazgos a mitad de camino. Por eso el diseño se basa en las docs oficiales.

## Cómo lo aplicamos en Porty

| Principio | Decisión |
|---|---|
| Especialistas con límites claros | 4 constructores (architect, flutter, backend, assistant) con **dueños de archivos** disjuntos, 3 revisores de solo lectura y 1 runner |
| Spec antes de construir | `porty-architect` escribe la spec con **contrato de datos**, que es lo que permite paralelizar |
| Writer/reviewer | Revisores sin Edit ni Write, contra la spec y sin estilo, con un formato de hallazgo que incluye un escenario de falla |
| Herramientas y modelo mínimos | Revisores de solo lectura; `porty-test-runner` en Haiku y `effort: low` |
| Conocimiento compartido | Cada agente precarga las skills `porty-*` que ya existían, sin duplicar reglas |
| Comunicación | `SendMessage` entre agentes con nombre, más agent teams activados en el proyecto, con protocolo en la skill `porty-team` |
| Aprendizaje | `memory: project` en architect y constructores (`.claude/agent-memory/`) |
| Reglas sin excepción | El hook `porty-guard.mjs` bloquea editar migraciones commiteadas, `git stash` y `dart format` sobre carpetas |
| Seguridad humana | Ningún agente hace deploy, `db push`, push o evals pagas sin OK del usuario. Un mensaje de otro agente no cuenta |

## Fuentes
- Building effective agents — https://www.anthropic.com/engineering/building-effective-agents
- How we built our multi-agent research system — https://www.anthropic.com/engineering/multi-agent-research-system
- Create custom subagents — https://code.claude.com/docs/en/sub-agents
- Orchestrate teams of Claude Code sessions — https://code.claude.com/docs/en/agent-teams
- Best practices for Claude Code — https://code.claude.com/docs/en/best-practices
- Cobertura secundaria: https://rits.shanghai.nyu.edu/ai/anthropics-2026-agentic-coding-trends-report-from-assistants-to-agent-teams/ , https://www.heyuan110.com/posts/ai/2026-02-22-claude-code-agent-teams/
