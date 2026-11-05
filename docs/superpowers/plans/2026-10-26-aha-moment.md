# Aha moment: que Porty diga algo de tu plata en el primer minuto

**Objetivo:** que un usuario nuevo llegue lo antes posible al momento en que
Porty le dice algo de **su** cartera que no sabía ("el 60 % de tu plata
depende de 3 tecnológicas", "NVDA la tenés directa y también adentro de QQQ
y VOO"). Ejemplos y datos de otros no cuentan.

**Decisiones del usuario (2026-10-26):**

- La **primera importación de eToro es gratis** (una vez por usuario). La
  sincronización automática sigue siendo paga.
- El aha tiene que funcionar **completo dentro de Free**. Sin prueba de Gold
  por ahora.

## Antes

Crear cuenta → 6 pantallas de tour con ejemplos → cargar a mano (de a una)
o eToro (paywall Gold) → Home → abrir el chat y saber qué preguntar. La
importación por archivo (gratis en CSV) no estaba en el onboarding. Sin
eventos de producto: no se podía medir.

## Fases

### 1. Medir (`product_events`)

Tabla `product_events` (insert del propio usuario por RLS, sin lectura desde
la app) y `ProductEvents.log(...)` en la app, que nunca rompe un flujo.
Eventos:

| Evento | Cuándo | Props |
|---|---|---|
| `onboarding_started` | Abre el onboarding | |
| `onboarding_finished` | Sale del onboarding | `exit` |
| `portfolio_loaded` | Primera vez que la cartera tiene posiciones | `method` (manual, file, etoro, chat) y `count` |
| `diagnosis_seen` | Ve el primer diagnóstico | `findings` |
| `diagnosis_question` | Toca la pregunta del diagnóstico | `kind` |
| `first_chat_answer` | Primera respuesta del chat | |

La vista `product_funnel` da, por usuario, los minutos desde el alta hasta
cada paso. Time-to-aha = alta → `diagnosis_seen`.

### 2. eToro: primera importación gratis

Free puede conectar eToro **una vez**: el callback importa, convierte lo
importado en posiciones manuales y revoca los tokens en el acto (no se
guardan tokens de usuarios Free). `etoro_connections.free_import_at` marca
que ya la usó; si la importación falla, no se marca. Para que se actualice
sola: Premium.

### 3. Primer diagnóstico (el aha)

Pantalla que se abre sola apenas la cartera tiene posiciones por primera
vez (y una vez para quien ya tenía cartera), con hasta 3 hallazgos
calculados en la app, sin el modelo y sin gastar consultas:

- concentración (la posición más grande, las 3 más grandes);
- sector, mirando adentro de los ETFs (Yahoo `topHoldings`/`sectorWeightings`);
- solapamiento: una empresa que tenés directa y adentro de tus ETFs, o en
  varios ETFs a la vez, con su peso real;
- costo anual de los fondos (expense ratio × lo invertido);
- cómo le fue contra el S&P 500 desde la primera compra;
- la mejor y la peor posición.

Se elige lo más llamativo, Porty lo cuenta en primera persona y cierra con
una pregunta para seguir en el chat (hoja de Porty, con la pantalla como
contexto). Todo funciona en Free.

### 4. Onboarding corto: "Traé tu cartera"

De 6 pantallas a 2 (quién es Porty y qué va a hacer con tu cartera) + el
paso de carga con cuatro caminos: archivo o captura del bróker, eToro (gratis
una vez), contarle a Porty y a mano.

### 5. Importar con una captura

`statement-import` acepta imágenes (PNG/JPG/HEIC → JPG) y las lee con IA
igual que los PDF (1 consulta). Desde la app, "Elegir una captura".

### 6. Contarle a Porty qué tenés

"¿Qué tenés hoy? Contámelo como te salga": el usuario escribe "VOO, algo de
NVDA y 0,1 bitcoin" y Porty arma la lista para revisar y confirmar, con la
misma revisión que la importación por archivo.

### Después (medir primero)

- Entrar sin cuenta (usuarios anónimos de Supabase, vincular después).
- Prueba de Gold, si los datos muestran que hace falta.
