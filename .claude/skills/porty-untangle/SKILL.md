---
name: porty-untangle
description: Desenredar un área de Porty (una feature, una capa o un archivo grande) para que un cambio típico caiga en un solo lugar - buscar vínculos ocultos, vínculos innecesarios, código que sobra y casos especiales, proponer los arreglos y aplicarlos en commits chicos con tests. Usar cuando el usuario pida refactorizar, ordenar, simplificar o "desenredar" código, o cuando un mismo cambio haya tenido que repetirse en varios archivos. Adaptada de caldoai/skills untangle-codebase.
argument-hint: "<área: carpeta, feature o archivo>"
---

# Desenredar un área de Porty

Objetivo: que quien trabaje en el área (persona o agente) lea menos por cambio, rompa menos sin darse cuenta y encuentre la causa de un bug más rápido. **El comportamiento queda igual**, salvo los bugs que el arreglo corrige (cada uno con su test).

## Límites (no negociables)

- **Siempre un área**, nunca el repo entero. Si el usuario no la dio, preguntá cuál o proponé la de más palanca (lo que más cambia junto en `git log`).
- **No borrar comentarios por estilo.** Los comentarios de Porty explican el porqué de producto o UX y son lo que más le sirve a un agente. Solo se van los que el arreglo deja falsos o los de un workaround que el arreglo elimina.
- **No borrar tests** por "no atraparían un bug". Un test que se acopla a internals se reescribe contra el comportamiento; uno que no puede fallar se le avisa al usuario, no se borra solo. Nunca tocar `test/security`, `test/branding` ni los del catálogo para que pasen.
- **Presupuesto de tokens** (ver CLAUDE.md): hacelo vos. A lo sumo un subagente de solo lectura (`Explore`) para resumir un área grande. No hay rondas de "repetir con subagentes hasta que no quede nada".
- Respetá los dueños de carpeta de `porty-team` y los hooks (migraciones commiteadas, `git stash`, `dart format` por archivo).

## 1. Línea base

```bash
flutter analyze 2>&1 | grep -E "^\s*(info|warning|error)" | sed 's/:[0-9]*:[0-9]* •/ •/' | sort > <scratchpad>/analyze_base.txt
flutter test <carpetas del área y de lo que la usa>
```

Anotá cuántos pasan y cuántos se saltean. Si Flutter no está, instalá la versión de CI (`flutter-version` en `.github/workflows`) antes de tocar nada.

## 2. Diagnóstico (sin cambiar nada)

Recorré el área con una sola pregunta: **¿estas piezas cambian juntas?** Anotá cada lugar donde el código responde mal, con `archivo:línea`:

**Vínculos ocultos** (tienen que cambiar juntas y el código no lo muestra)
- Copias de lógica o valores: dos notifiers con el mismo flujo, la misma regla en la pantalla y en el provider.
- Estado que escriben dos lugares sin que nada lo diga (ej.: un flag que cambian el turno y un listener).
- Un orden de llamadas o convención que el que llama "tiene que saber".

**Vínculos innecesarios** (están atadas y cambian por razones distintas)
- Una pantalla que lee internals de un notifier en vez de un getter con nombre.
- Código estable que importa algo más volátil.
- Una función general con un parámetro que solo entiende un flujo.

**Sobra** (no tiene razón propia para cambiar)
- Wrappers que solo pasan la llamada, configuración para cosas que nunca varían, código muerto (`grep` sin usos).

**Casos especiales** (síntomas de un requisito que el diseño no contempla)
- Un `if` para un valor, un `catch` que atrapa un solo tipo y deja el resto colgado, un reintento o `sleep`, un flag `busy` que no dice qué está ocupado, un test salteado.

Usá `git log --name-only` como evidencia de qué cambia junto.

## 3. Arreglos

Para cada grupo de problemas, buscá **el arreglo de fondo que resuelve varios a la vez**, no un parche por caso. Escribí el log así (en el scratchpad, y resumido al usuario):

```md
- Un `BrokerActivity` compartido y un helper `_run` que hace guard + actividad + error + recarga.
  - `binance_provider.dart:60` repite guard/activity/try/catch en cada acción.
  - `snaptrade_provider.dart:68` ídem, con 5 acciones.
```

Cada arreglo tiene que cumplir: lo que cambia junto queda junto, lo que no cambia junto no queda atado, y todo depende de lo que cambia menos.

**Pará y mostrale la lista al usuario.** Él elige qué se hace (recomendá un orden).

## 4. Aplicar

- Un arreglo por commit, con mensaje que diga qué problema resuelve.
- Si el arreglo corrige un bug: test que **falla con el código anterior** y pasa con el nuevo (compará copiando el archivo viejo con `git show HEAD:<ruta>` al lugar y restaurando desde el scratchpad).
- Tests del área y de quien la usa después de cada arreglo; `dart format` solo sobre los archivos tocados.

## 5. Cierre

- `flutter test` completo y `flutter analyze` comparado contra la línea base: ningún aviso nuevo.
- Reporte al usuario: qué se arregló (y qué bug salió de paso), qué se dejó a propósito y por qué, y qué queda pendiente.
- Commit sí; push o PR solo con el OK del usuario.

Listo cuando: un cambio típico del área cae en un solo lugar, quedan los menos casos especiales posibles y los imports van de lo volátil a lo estable.
