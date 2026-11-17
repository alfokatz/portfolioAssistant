---
name: porty-verify
description: Cómo verificar que un cambio de Porty funciona antes de decir "listo", commitear o abrir un PR - verificación rápida por archivos tocados (tools/verify/verify.sh), stack local de Supabase, tests Deno/SQL y E2E real de la app web con Playwright (tools/verify/e2e). Usar SIEMPRE al terminar un cambio de código en lib/, test/ o supabase/, al arreglar un bug, o cuando el usuario pida probar, verificar o hacer una prueba de humo.
---

# Verificar un cambio en Porty

Verificar es **correr el cambio**, no solo leerlo. Lo barato primero; lo caro antes del commit.
Si algo falla, arreglalo y volvé a correr. **Tres rondas sin resolverlo → pará y avisale al usuario**
qué falla, qué probaste y tu mejor hipótesis.

## 0. Requisitos del entorno

`flutter`, `deno` y `supabase` instalados (en cloud los instala `tools/dev/cloud-setup.sh`).
Si falta alguno, no inventes resultados: decí qué no pudiste correr y poné `Verified: none — <motivo>`.

## 1. Rápido (siempre): `tools/verify/verify.sh`

```bash
tools/verify/verify.sh                 # contra origin/main
tools/verify/verify.sh --base develop  # si el PR va a otra rama
```

Mira qué archivos cambiaron y corre solo lo relacionado: `dart analyze` de los `.dart` tocados,
`flutter test` de las carpetas de test que corresponden (`lib/features/x` → `test/features/x`),
`test/branding` si cambiaron traducciones, `test/security` si cambió el chat, y `deno check` +
`deno test` de las edge functions tocadas. Tarda ~30 s en un cambio típico.
Termina con una línea `Verified: …` lista para pegar en el commit.

Si un archivo nuevo de `lib/` no tiene carpeta de test, `verify.sh` no corre tests: escribí el test
(skill **porty-testing**) o decilo.

## 2. Backend (si tocaste `supabase/`)

```bash
eval "$(tools/verify/supabase-env.sh)"   # levanta Docker + Supabase local y exporta las claves
tools/verify/verify.sh                   # ahora los tests de Deno tienen SUPABASE_URL
tools/verify/sql-tests.sh                # tests SQL (todas las migraciones aplicadas en limpio)
```

La primera vez baja imágenes (~3-5 min). Nunca uses el proyecto remoto para verificar.

## 3. E2E (si cambiaste un flujo que ve el usuario)

```bash
tools/verify/e2e/run.sh                          # todos los flujos (~2 min de build + ~1 min)
tools/verify/e2e/run.sh cargar-posicion-a-mano   # uno o varios, separados por coma
E2E_SKIP_BUILD=1 tools/verify/e2e/run.sh         # reusar build/web si no tocaste lib/
```

Compila la app para web contra el Supabase local, crea un usuario nuevo y la maneja con Playwright
como una persona. Si un paso falla, el reporte dice **qué paso** y deja una captura en
`build/e2e/<flujo>-FALLA.png`: **mirala** (Read) antes de tocar código.

Flujos actuales (`tools/verify/e2e/flows.mjs`): arranque, login con clave incorrecta,
login → onboarding → inicio vacío, cargar una posición a mano, Ajustes → cerrar sesión.

**Cuándo agregar un flujo:** feature nueva con un camino del usuario de punta a punta, o un bug que
llegó al usuario y se puede reproducir clickeando. Cada paso describe lo que ve el usuario.
Escribí en los campos con `typeInto` (no `fill`), scrolleá con `scrollTo` y esperá textos con `seen`.

**Límites:** web no tiene widget de inicio, push, RevenueCat ni el proxy de IA real (los errores
`MissingPluginException` de `home_widget` en consola son esperables). El chat y las compras se
verifican con los tests de Flutter/Deno y las evals (pagas: solo con OK del usuario).

## 4. UI (si cambió algo visible)

Capturas por variable de entorno (skill **porty-testing**) y revisión contra `DESIGN.md`
(skill **porty-ui-design**). El E2E también deja `build/e2e/<flujo>-ok.png`.

## 5. Antes de abrir un PR

```bash
tools/verify/check-controls.sh --base main   # ¿mezclé controles con código? ¿todos los commits tienen Verified:?
```

El CI corre lo mismo (job `controles`, con el script de la rama base) y el E2E (job `e2e`), ambos en
modo observe. Cómo y cuándo pasarlos a enforce: `docs/runbooks/ci-cd.md`.

## Reglas

- **Tests inestables:** prohibido reintentar hasta que pase, agregar `sleep`/esperas fijas o saltearlos.
  Buscá la causa (ej.: el E2E perdía el primer campo con `fill()`; la causa era el foco de Flutter web,
  no la app). Si no la encontrás, borrá el test y explicá por qué en el commit.
- **Evidencia, no fe:** en tu respuesta decí qué corriste y el resultado. En el commit,
  `Verified: <comandos>` o `Verified: none — <motivo>`.
- **No modifiques el verificador en el mismo cambio que juzga** (`tools/verify/`, `REVIEW.md`,
  hooks): va aparte, con OK del usuario.
- El hook `Stop` (`.claude/hooks/porty-verify-gate.mjs`) anota en `.claude/verify-gate.log` cada
  turno que terminó con código cambiado y sin verificación (modo `observe`). En `enforce` te va a
  frenar una vez para que verifiques.
