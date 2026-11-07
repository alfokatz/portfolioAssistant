# Loaders, movimiento y haptics

## Loaders (`lib/presentation/shared/loading/`)

| Espera | Loader |
|---|---|
| Contenido con layout conocido (listas, Home, gráficos, previews) | `SkeletonScope` + `SkeletonBlock` (`.line`, `.circle`), o `SkeletonText` |
| Espera sin estructura (arranque, informe semanal) | `PortyLoader` |
| Acción de un botón | `LoadingButtonContent` / `ButtonSpinner` (el único spinner de la app) |
| Dentro del chat | `QaSkeleton`, `QaChartSkeleton` |

Regla de tiempos (`LoaderTiming`): aparece a los **300 ms** (esperas más cortas no muestran nada), una vez visible queda **400 ms** mínimo, cruce de **200 ms** `easeOutCubic`, la frase de `PortyLoader` aparece a los 2 s.

```dart
LoadingSwitcher(
  loading: !state.loaded,
  placeholder: (_) => const GoalsSkeleton(),
  child: (_) => GoalsList(goals: state.goals),
)
```

- `PortyLoader` no aplica la regla solo: siempre dentro de `LoadingSwitcher` / `DelayedLoaderVisibility`.
- Un skeleton nunca simula datos (sin texto ni números falsos) y tiene la misma forma que el contenido final, para que nada salte.
- Ejemplo: `lib/presentation/flows/home/ui/widgets/home_skeleton.dart`.

## Movimiento

- Transiciones de estado: 150–250 ms, `Curves.easeOutCubic`. Entradas de cards del chat: `RevealTiming` (`catalog/widgets/reveal_step.dart`). Cambios de valor en el chat: `QaStateMotion` (240 ms).
- Cambio de estado de la app (login → home): `FadeThroughPage` (400 ms, opaco).
- Reduce motion, siempre:
  ```dart
  final reduce = MediaQuery.disableAnimationsOf(context);
  duration: reduce ? Duration.zero : const Duration(milliseconds: 200),
  ```
  `MotionAwareSize` en lugar de `AnimatedSize` (que tira assert con duración cero); `startRevealAnimation(controller, skip: reduce, ...)` para "aparecer una vez".
- El espacio se cierra, no salta: `MotionAwareSize`, `SkeletonText`, `QaStateSwitcher`.
- Sin animaciones decorativas en loop salvo Porty (`PortyAvatar`), que ya maneja las suyas.

## Haptics

Solo por `PortyHapticsService.maybeOf(context)?.<evento>()` (respeta el ajuste del usuario): `selectionTap`, `lockedTap`, `paywallOpened`, `authSucceeded`, `authFailed`, `brokerSynced`, `brokerFailed`, etc. Tono: nunca un golpe de celebración; errores = dos toques leves. Nunca `HapticFeedback.*` directo.
