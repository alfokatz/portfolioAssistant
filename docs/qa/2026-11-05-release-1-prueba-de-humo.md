# Release 1 de Porty: prueba de humo manual

Fecha: 2026-11-05 · Rama: `feature/ui_redesign` (commit `aa25888`, Porty bilingüe) · Duración estimada: 30-45 min (los bloques marcados "extra" son opcionales y suman 15 min).

Cómo usarla: andá en orden, tildá cada casilla `[ ]` y anotá al margen lo que falle. Los pasos con ⛔ **bloquean la publicación**: si uno falla, no se manda a las tiendas hasta arreglarlo. El resto, si falla, se anota como bug y se decide.

Notación de textos: `EN / ES` = lo que dice la pantalla en inglés / español. Si coinciden, va una sola vez.

---

## 0. Antes de empezar (preparación, 5 min)

Necesitás:

- Un teléfono real (idealmente uno iPhone y uno Android; si tenés uno solo, hacé todo ahí y dejá la sección 13 para después).
- Build de release (TestFlight / pista interna de Play), no debug. Si ves el cartel "DEBUG", no es el build correcto.
- Cuenta sandbox de Apple (Ajustes > App Store > Cuenta de sandbox) y/o cuenta de prueba de licencias en Google Play.
- Dos mails nuevos para altas (uno para email+contraseña, otro de respaldo) y la cuenta de Google/Apple del teléfono.
- Una captura de pantalla o PDF/CSV de un bróker con 3-5 posiciones, guardada en el teléfono.
- Otro teléfono (o el mismo con el idioma cambiado) para la prueba "usuario inglés que nunca vio español".

Precondiciones de servidor:

- [ ] ⛔ **P1.** `ai-chat` desplegado con el allowlist nuevo del commit `aa25888` (hashes del prompt). Cómo saberlo: en el paso 5.1 el chat responde en inglés sin error "unauthorized" / sin respuesta vacía. Si no, avisar a `porty-backend-dev` y desplegar antes de seguir (el despliegue lo autorizás vos).
- [ ] **P2.** Interruptores en `app_config` prendidos al 100 % (decisión del 05/11): `market_taste`, `weekly_report_courtesy`, `quota_nudge`, `diagnosis_bridge`, `broker_screenshot_exit`. `paywall_annual` es aparte: el selector Mensual/Anual solo aparece si está prendido y la tienda devuelve productos anuales.
- [ ] **P3.** RevenueCat: productos `portfolio_premium_monthly`, `portfolio_gold_monthly` (y los anuales `portfolio_premium_annual`, `portfolio_gold_annual`) aprobados/disponibles en sandbox, y el webhook `revenuecat-webhook` activo.

Datos de planes para contrastar (de `lib/domain/subscription/plan_matrix.dart`): Free = 20 consultas/mes, 10 posiciones, watchlist de 3, 3 consultas de mercado de degustación por mes; Premium = 500 consultas, posiciones sin límite; Gold = 1000 consultas.

Navegación de la app: barra inferior con 4 pestañas: **Home / Inicio**, **Porty**, **Goals / Metas**, **Settings / Ajustes**.

---

## 1. Instalación y alta (6 min)

Empezá con el teléfono **en inglés** (Ajustes del sistema > Idioma: English). Desinstalá Porty si estaba.

- [ ] ⛔ **1.1** Instalar y abrir. Esperado: aparece el logo/loader de Porty y, en la pantalla de carga, frases en inglés ("Getting your portfolio ready…", "Connecting to your account…"), sin cartel de debug, sin pantalla blanca ni crash. Termina en el login.
- [ ] ⛔ **1.2** Login en inglés. Esperado: "Hi, I'm Porty. Sign in and I'll tell you how your investments are doing." / ES "Hola, soy Porty. Entrá y te cuento cómo van tus inversiones."; botones "Sign in", "Continue with Google", (solo iPhone) "Continue with Apple"; pestaña "Sign up". Nada en español.
- [ ] **1.3** En Android, el botón de Apple **no** aparece. En iPhone sí.
- [ ] **1.4** Tocar "Terms and conditions" y "Privacy policy" (en la pestaña Sign up, texto "By signing up you accept the…"). Esperado: abren la web (`portyassistant.com/app/terminos` y `/app/privacidad`). Anotar si la página está en inglés o solo en español (ver Riesgos).
- [ ] ⛔ **1.5 Alta con email.** Pestaña "Sign up": nombre completo, email, contraseña (probá primero una floja: "abc" y mirá los avisos "8+ characters / Upper and lowercase / A number" y la barra WEAK/MEDIUM/STRONG), confirmar contraseña, "Create account". Esperado: pantalla "Check your email" / "Revisá tu email" con "We sent a confirmation link to…".
- [ ] ⛔ **1.6** Abrir el mail de confirmación en el teléfono y tocar el link. Esperado: vuelve a la app con la sesión iniciada y entra al onboarding (no queda en el login ni en una página web muerta). Si el link llega y dice "expirado": reportar.
- [ ] **1.7** Mails de Supabase (confirmación y reset): anotar el idioma del mail (probablemente un solo idioma para todos; ver Riesgos).
- [ ] **1.8** Error de login: con la cuenta recién creada, poner mal la contraseña. Esperado: "The email or password is incorrect." / "El email o la contraseña no son correctos." (sin texto técnico).
- [ ] **1.9** "Forgot your password?" / "¿Olvidaste tu contraseña?": poner el email, enviar. Esperado: "If there's an account with that email, you'll get a link to reset…". Abrir el link: pantalla de nueva contraseña; cambiarla; entra a la app. Probá que después la contraseña vieja ya no sirve.
- [ ] ⛔ **1.10 Alta con Google.** Cerrar sesión (Settings > "Sign out") y entrar con "Continue with Google". Esperado: hoja de Google, vuelve a la app logueado. Cancelar a mitad del flujo no deja la app trabada ("Connecting…" infinito).
- [ ] ⛔ **1.11 Alta con Apple (solo iPhone).** "Continue with Apple" con "Ocultar mi correo" activado. Esperado: entra; el nombre/mail aparecen razonables en Settings (con mail oculto aparece el relay de Apple, sin romperse).
- [ ] **1.12** Cerrar la app del todo y reabrirla. Esperado: sigue logueado, sin pasar por el login (sesión restaurada).

---

## 2. Onboarding y primera carga de cartera (6 min)

Usá la cuenta nueva (sin posiciones). El teléfono sigue en inglés.

- [ ] ⛔ **2.1** Primera pantalla: "Hi, I'm Porty" / "Hola, soy Porty", ejemplos ("How much NVDA really weighs, counting your ETFs"…), etiqueta "Example", botón "Get started" / "Empezar". Indicador "Step 1 of N". Todo en inglés.
- [ ] ⛔ **2.2** Segunda pantalla "Bring your portfolio" / "Traé tu cartera" con las opciones: "A file or screenshot from your broker", "Tell Porty what you own", "Add it by hand", "Connect your broker" y la salida "Not now" / "Ahora no". Esperado: cada una entra a su flujo sin crash y se puede volver.
- [ ] **2.3** Disclaimer: aparece "Porty offers educational information: it isn't financial advice…" (texto de `onboarding_finish_disclaimer`) en el cierre del onboarding o en la pantalla correspondiente.
- [ ] ⛔ **2.4 Camino captura.** "A file or screenshot from your broker": elegir la captura/archivo preparado. Esperado: Porty lee las posiciones, muestra una pantalla de revisión (ticker, cantidad) editable, confirma y guarda. Las posiciones aparecen en Home. Probá también un archivo basura (una foto de un perro): mensaje de error claro, no crash.
- [ ] **2.5 Camino "Tell Porty what you own".** Escribir "10 VOO and some NVDA". Esperado: Porty entiende o pide aclarar la cantidad de NVDA; no inventa un número sin preguntar.
- [ ] ⛔ **2.6 Camino manual.** Crear una cuenta/volver: "Add it by hand" / "Add position": "What did you buy?" > ticker `AAPL`; "How much did you buy?" cantidad 3; fecha de hoy. Esperado: "Today $xxx" con el precio; botón "Add to my portfolio" / "Agregar a mi cartera"; aparece en Home.
- [ ] **2.7 Datos raros (alta manual).** Probar, uno por uno, y anotar qué pasa (esperado: mensaje claro, nunca crash ni cifras absurdas):
  - Ticker inexistente `ZZZZXQ` > "Invalid ticker" / "Ticker inválido" o "I can't find ZZZZXQ…".
  - Cantidad 0 y cantidad negativa > "Quantity and price must be greater than zero".
  - Cantidad enorme `999999999999` > no desborda la pantalla ni muestra notación científica.
  - Fecha futura y fecha de hace 30 años.
  - Ticker en minúsculas `nvda`; ticker no estadounidense (`VOD.L`, `ASML.AS`); cripto (`BTC-USD`).
- [ ] **2.8 Conexión de brókers (extra, solo si tenés cuenta).** Settings > "Connect your broker" (o desde Home). Pantalla "Connect your broker" con tarjetas eToro, Binance, "Another broker" y el link "Broker not listed? Upload a statement or a screenshot". Esperado: texto "Read-only: Porty never buys, sells or moves your money". Como usuario Free, Binance y SnapTrade deben mostrarse **bloqueados con explicación** y con la salida "traela con una captura" (interruptor `broker_screenshot_exit`), nunca un botón muerto.
- [ ] **2.9** Cerrar y reabrir la app a mitad del onboarding. Esperado: retoma el onboarding, no te manda al login ni a un Home vacío roto.
- [ ] **2.10** Settings > "View tutorial again" / "Ver tutorial de nuevo" vuelve a mostrar el onboarding sin borrar nada.

---

## 3. Dashboard / Home (5 min)

Con 3-5 posiciones cargadas, plan Free.

- [ ] ⛔ **3.1** Encabezado: "Hi, <nombre>" / "Hola, <nombre>" y la fecha del día en inglés ("Thursday, November 5"). Al cerrar y reabrir no cambia el idioma.
- [ ] ⛔ **3.2** Total de cartera ("Total value") con valor, ganancia/pérdida y gráfico. Cambiar el rango: "Last week / Last month / Last 3 months / Last 6 months / Last year / Since your first purchase" / "Última semana… Desde tu primera compra". Esperado: el gráfico y el cambio se actualizan; sin parpadeos de error.
- [ ] **3.3** Arrastrar el dedo sobre el gráfico (scrub). Esperado: muestra fecha y valor del punto. Anotar el formato de fecha ("Nov 5, 2026") y moneda ("$2,058.00").
- [ ] ⛔ **3.4** Lista "My Positions" / "Mis posiciones" con ticker, cantidad ("3 shares" / "3 acciones" ... "1 share"), valor y % (verde/rojo). Pestañas "Assets / Activos" e "Insights". Tocar "View all" / "Ver todas" si hay más de las que entran.
- [ ] **3.5** Tarjeta "I looked at your portfolio" / "Miré tu cartera" (diagnóstico). Tocarla: abre el diagnóstico (`/diagnosis`) con texto en el idioma de la app y, al final, las filas del puente (interruptor `diagnosis_bridge`: "que se actualice sola" y "¿te aviso el sábado?"). Esperado: cada fila lleva a una pantalla que existe (conectar bróker / notificaciones).
- [ ] **3.6** Tarjeta "Against the market" / "Contra el mercado" (S&P 500). En Free debería verse bloqueada: "Compare your portfolio with the S&P 500 on Premium" / "Compará tu cartera con el S&P 500 en Premium" y al tocar abre el paywall (no una pantalla en blanco).
- [ ] **3.7** Tocar una posición: detalle (`/position/detail`) con valor, ganancia, cantidad, precio promedio, lotes. Esperado: sin valores "NaN", "null" ni "$0.00" falsos.
- [ ] **3.8** En el detalle, vender/cerrar la posición (pantalla "Close position"): cantidad parcial, precio, resultado antes de confirmar. Confirmar. Esperado: pasa a "Closed positions" / "Posiciones cerradas" (tarjeta en Home con el historial) y el total se actualiza. Probar cantidad mayor a la que tenés > error claro.
- [ ] **3.9** Borrar una posición (deslizar o menú en la fila). Esperado: hoja de confirmación "exactamente lo que va a pasar", no un diálogo genérico; al confirmar, desaparece.
- [ ] **3.10** Settings > "Currency" / "Moneda": elegir UYU (o ARS). Esperado: debajo del total aparece la cartera en esa moneda; volver a USD la saca. Sin cotización (sin red) no muestra números inventados.
- [ ] **3.11** Pull to refresh en Home. Esperado: spinner y actualización; sin duplicar posiciones.
- [ ] **3.12** Watchlist: tarjeta/entrada "Watchlist" / "Lista de seguimiento". Como Free, seguir 3 tickers y al intentar el cuarto debe explicar el límite (no error técnico).

---

## 4. Chat con Porty (10 min)

Pestaña **Porty**. Cuenta Free con posiciones cargadas. App en inglés.

- [ ] ⛔ **4.1** Pantalla de chat: bienvenida "Hi, I'm Porty. Ask me anything: your portfolio, investing co…" / "Hola, soy Porty. Preguntame lo que quieras…", sugerencias ("What moved my portfolio this week?", "Am I too concentrated?") y el campo "Type your question..." / "Escribí tu pregunta...". Aviso "Educational information only. Not financial advice…" visible.
- [ ] ⛔ **4.2** Mandar la **pregunta E1** de la lista de abajo. Esperado: "Porty is generating a response" (indicador), respuesta en menos de ~20 s, en inglés, con una card.
- [ ] ⛔ **4.3** Recorrer las preguntas **E1 a E10** (lista en la sección 4 bis). Para cada una anotar: idioma de la respuesta y de la card, si la card se ve completa (sin texto cortado ni "null"), y si el tono es educativo y sin "comprá / vendé".
- [ ] ⛔ **4.4** Cards en inglés: en las respuestas con card (posiciones, concentración, mejores/peores, comparación, plan de ahorro, propuesta de acción) todos los títulos, etiquetas y botones deben estar en inglés. Cualquier palabra en español en la card = bug (adjuntar captura).
- [ ] ⛔ **4.5** Preguntas en español **S1 a S5** con la app todavía en inglés. Esperado: Porty responde en **español** (se responde en el idioma de la pregunta) y la card, que es de la app, puede quedar en inglés. Anotar si hay mezcla rara dentro de una misma frase.
- [ ] **4.6** Cambiar la app a español (sección 9) y repetir S1-S3 y E1-E2. Esperado: respuesta y cards en español; una pregunta en inglés con app en español responde en inglés.
- [ ] ⛔ **4.7 Acción desde el chat (E9).** Porty propone registrar la compra con una card de confirmación ("Check the details and confirm to save it to your portfolio."). Confirmar: "VOO purchase saved" / "Compra de VOO registrada" y aparece en Home. Cancelar/no confirmar: no se guarda nada.
- [ ] **4.8** Plan de ahorro (E8): la card trae un botón para guardar en Metas. Tocar: "Goal saved in Goals" / mensaje equivalente y aparece en la pestaña Goals / Metas.
- [ ] ⛔ **4.9 Degustación de mercado (Free).** Preguntar por un ticker que no tenés (E5 `NVDA` si no lo tenés). Esperado: responde con precio/gráfico y debajo "Free market lookup · 2 left this month" / "Consulta de mercado gratis · te quedan 2". Repetir dos veces más: la tercera dice "that was the last one this month" / "era la última de este mes". La cuarta no corta el turno: Porty contesta pero con el aviso "Premium shows prices, charts and comparisons for any ticker" y botón "See Premium" / "Ver Premium".
- [ ] ⛔ **4.10 Cuota Free (20/mes).** No hace falta gastar las 20. Verificar el contador abriendo el paywall desde Settings (muestra "N/20 queries this month" / "N/20 consultas este mes"). Cuando quedan pocas debe aparecer la línea "You have N queries left this month… See plans" / "Te quedan N consultas este mes… Ver planes" (interruptor `quota_nudge`). Extra (opcional, con cuenta descartable): agotar la cuota y comprobar el bloqueo "Queries exhausted" / "Consultas agotadas" con botón al paywall, sin perder el texto que escribiste.
- [ ] **4.11** Estados raros del chat: (a) mensaje vacío: el botón enviar no hace nada; (b) mensaje larguísimo (pegá 3000 caracteres): no rompe; (c) ticker inexistente ("What is the price of ZZZZXQ?"): "I couldn't find a valid ticker…" o similar, sin card rota; (d) pregunta sin posiciones (cuenta nueva): "Add open or closed positions so I can answer using your data".
- [ ] **4.12** Dictado por micrófono (icono "Dictate message" / "Dictar mensaje"). Primera vez: pide permiso. Anotar en qué idioma está el diálogo de permiso en iPhone (ver Riesgos). Hablar en inglés con la app en inglés: transcribe bien. Si negás el permiso: mensaje "To dictate, allow Porty to use the microphone…" sin crash.
- [ ] **4.13** Pedir ayuda "diagnóstica": preguntar E10 ("Should I sell everything…"). Esperado: nada de recomendaciones personalizadas imperativas; aparece el disclaimer; tono educativo. (Si Porty dice "vendé todo", bug crítico de compliance.)
- [ ] **4.14** Cerrar y reabrir el chat. Esperado: la conversación se conserva o arranca limpia de forma coherente; no queda "Porty is generating…" colgado.

### 4 bis. Preguntas para probar

**Inglés (10)**

| # | Pregunta | Qué debería pasar |
|---|---|---|
| E1 | How is my portfolio doing today? | Foto de posiciones / valor del día, en inglés |
| E2 | What moved my portfolio this week? | Explica los que más movieron (puede pedir Premium si es "por qué"), sin inventar |
| E3 | Am I too concentrated in one stock? | Card de concentración (barra por posición) |
| E4 | Which of my positions is doing best and which is doing worst? | Card "mejores y peores" comparando dos |
| E5 | How is NVDA doing? (un ticker que no tenés) | Degustación de mercado Free, con contador "left this month" |
| E6 | Compare AAPL and MSFT | Card de comparación lado a lado; en Free, consume degustación o muestra teaser Premium |
| E7 | What is diversification? Explain it simply. | Respuesta educativa, sin gastar consulta de mercado |
| E8 | I want to save $10,000 in 2 years. How much per month? | Card de plan de ahorro, con botón para guardar en Goals; en Free puede aparecer paywall de metas (debe explicarse bien) |
| E9 | I bought 5 shares of VOO yesterday at $500 | Card de propuesta de acción para confirmar |
| E10 | Should I sell everything and buy Bitcoin? | Respuesta educativa con disclaimer, sin imperativo |

**Español (5)**

| # | Pregunta | Qué debería pasar |
|---|---|---|
| S1 | ¿Cómo viene mi cartera esta semana? | Respuesta en español |
| S2 | ¿Cuánto pesa cada posición en mi cartera? | Card de concentración, respuesta en español |
| S3 | Quiero juntar 5000 dólares en 18 meses, ¿cuánto tengo que ahorrar por mes? | Plan de ahorro, importes con formato consistente |
| S4 | ¿Qué es un ETF y en qué se diferencia de una acción? | Educativa, sin consumir mercado |
| S5 | Compré 10 acciones de AAPL a 190 dólares hoy | Card de confirmación de compra |

Pruebas cruzadas rápidas (1 minuto): con la app en inglés mandar S4; con la app en español mandar E7. Esperado: cada una se responde en el idioma de la pregunta.

---

## 5. Informe semanal (3 min)

El informe cubre la semana lunes-viernes cerrada y se habilita el **sábado 00:00 hora local**. Hoy es jueves 05/11: de lunes a viernes se muestra el de la semana **anterior**. Si la cuenta es nueva y sin historial, la tarjeta puede no aparecer (se oculta sin posiciones o sin datos de la semana): en ese caso usá una cuenta con cartera vieja o repetí este bloque el sábado.

- [ ] **5.1** En Home aparece la tarjeta "Your week" / "Tu semana" (con "Porty is preparing your week…" / "Porty está preparando tu semana…" mientras genera). Tocarla abre el informe (`/weekly-report`).
- [ ] ⛔ **5.2** Informe en inglés completo: grupos "How you did", "Why", "What's next", "Go deeper"; fechas "September 21–25" (ES "21 al 25 de septiembre"); "The S&P 500 rose 1.2%"; frase de Porty en inglés; disclaimer "Informational, not financial advice…". Cero palabras en español. Gráfico con "Your portfolio" y "S&P 500".
- [ ] **5.3 Free: degustación.** Debe verse el informe completo con el aviso "This full report is on us. With Gold, you get it every…" (o "Full report on us, 1 of N" / "This is your last full report on us"). Segunda vez, sin Gold: bloqueo "What explains your week is in Gold" / "Lo que explica tu semana está en Gold" con botón al paywall, mostrando igual los números.
- [ ] **5.4** Si Porty no pudo escribir: "Porty couldn't write its part this week. The numbers are…" y los números siguen visibles (no pantalla vacía).
- [ ] **5.5** Preguntas de seguimiento al final ("What happened with <TICKER> this week?", "How am I doing this year?") abren el chat con esa pregunta ya enviada.
- [ ] **5.6** Cambiar el idioma después de generado el informe (ver sección 9): anotar en qué idioma queda el texto escrito por Porty (se sospecha que queda en el idioma original; ver Riesgos).

---

## 6. Metas (3 min)

- [ ] ⛔ **6.1** Pestaña Goals / Metas sin metas: "Tell me what you want to achieve and I'll build you a plan…", "You can start with one of these" con ideas (emergency fund, trip, purchase, retirement) y botón "Build a goal with Porty" / "Armar una meta con Porty". Todo en inglés.
- [ ] **6.2** Tocar una idea ("An emergency fund"): abre el chat con "I want to build an emergency fund". Seguir la conversación hasta que Porty arme el plan y guardarlo.
- [ ] **6.3** La meta aparece en "In progress" / "En curso" con monto objetivo, fecha y estado ("Just started / On track / Behind"). Abrirla (`/goal/:id`): "Porty's plan", "Monthly savings", "Time left", "Where to invest it".
- [ ] **6.4** Opciones de la meta (icono "Show options"): "Edit plan", "Mark as achieved" (pasa a "Achieved"), "Make active again", "Delete goal" con confirmación "Delete the goal "X"?". Verificar cada una.
- [ ] **6.5** "Savings outside the app" (Bank, cash or another broker): cargar un monto y ver que el progreso cambia.
- [ ] **6.6** Como Free, si metas es de Premium: confirmar que el bloqueo muestra "Put a number on your goal" / "Ponele número a tu meta" (paywall) y no un error. Con montos raros: meta de $0, de $1,000,000,000, fecha en el pasado: mensajes claros, sin NaN.

---

## 7. Paywall y compra en sandbox (10 min)

⚠ Solo con cuentas sandbox/licencia de prueba. Nunca con tu tarjeta real.

- [ ] ⛔ **7.1** Abrir el paywall desde Settings > "Upgrade plan" / "Mejorar plan" (tarjeta de plan "Free Plan" / "Plan Free"). Esperado: "Choose your plan" / "Elegí tu plan" con Premium y Gold, "Recommended", precios ("$X/month" / "$X/mes") cargados desde la tienda (si dice "Price shown at checkout" / "Precio al confirmar la compra" la tienda no devolvió precio: anotar), texto de renovación "Renews every month at … Cancel anytime." y links "Terms" / "Privacy".
- [ ] **7.2** Si está el selector "Monthly / Annual" ("Mensual / Anual"): cambiar y ver que el precio y el "Save N% vs. monthly" cambian. Si no aparece, anotar (puede ser el interruptor `paywall_annual` apagado).
- [ ] ⛔ **7.3 Free > Premium.** Tocar "Upgrade to Premium" / "Actualizar a Premium" y completar con la cuenta sandbox. Esperado: "Plan activated! It may take a few seconds to update." / "¡Plan activado!…"; en menos de ~30 s Settings muestra "Premium Plan" / "Plan Premium" y la cuota sube a 500; el bloqueo del S&P 500 en Home desaparece.
- [ ] ⛔ **7.4 Premium > Gold.** Desde Settings > "Upgrade plan" > "Upgrade to Gold". Esperado: cambio de plan (no doble cobro), Settings dice "Gold Plan" / "Plan Gold" y "You have the most complete plan" / "Tenés el plan más completo". El informe semanal completo y "Why it moved" quedan habilitados.
- [ ] ⛔ **7.5 Restaurar compras.** Cerrar sesión, desinstalar, reinstalar, loguearse con la **misma** cuenta y tocar Settings > "Restore purchases" / "Restaurar compras". Esperado: "Purchases restored successfully." y el plan vuelve a Gold. Probar también "Restore" estando en Free sin compras: "Purchases restored…" o un aviso neutro, nunca error técnico.
- [ ] **7.6 Cancelar y vencer.** En el sandbox, cancelar la suscripción y esperar el vencimiento acelerado (en sandbox las renovaciones duran minutos). Esperado: la app vuelve a Free al vencer, sin crash y sin perder datos; la cartera sigue.
- [ ] **7.7 Compra cancelada.** Abrir una compra y tocar "Cancelar" en la hoja de la tienda. Esperado: vuelve al paywall sin mensaje de error alarmante.
- [ ] **7.8** Sin red durante la compra o al abrir el paywall: mensaje claro ("Could not complete the purchase. Please try again."), sin botones colgados.
- [ ] **7.9** Motivos de paywall: confirmar que el título/subtítulo cambia según de dónde venís (cuota: "Queries exhausted"; datos de mercado: "Market data not included in your plan"; límite de posiciones: "Bring your whole portfolio" con "Free covers up to 10 positions"; metas, simulaciones, plan de cartera). Cuando el motivo es de Premium, Premium se muestra primero (decisión 05/11).
- [ ] **7.10** Texto legal del paywall en la tienda correspondiente: "Payment is charged to your Apple ID / Google Play account at confirmation of purchase…" (nombre de tienda correcto en cada plataforma).
- [ ] **7.11** Después de cada compra, mirar en RevenueCat (dashboard) que el cliente tenga el entitlement `premium`/`gold` y que Supabase refleje el plan (si la app dice Gold pero el chat aún limita a 20, el webhook falló: bug de backend).

---

## 8. Notificaciones (3 min)

- [ ] ⛔ **8.1** Settings > "Notifications" / "Notificaciones". Primera vez: "Turn on notifications" / "Activar notificaciones" y el texto "Right now we can't notify you of anything." Tocar y aceptar el permiso del sistema. Esperado: pasa al estado activado con interruptores: "Price alerts", "Big moves", "Your portfolio today", "Weekly report", "Your companies' earnings", "Account notices".
- [ ] ⛔ **8.2** "Send me a test" / "Enviarme una de prueba": "Done. It will arrive in less than a minute." Esperado: llega la notificación push al teléfono (con la app en segundo plano) en el **idioma de la app**; al tocarla abre Porty.
- [ ] **8.3** Denegar permiso: reinstalar o revocar en Ajustes del sistema. Esperado: "Turned off on your phone" / "Desactivadas en el teléfono" con instrucciones, y no se rompe el resto de la pantalla.
- [ ] **8.4** Sensibilidad ("What counts as big": Only the big ones / Normal / More notifications), silencio ("Quiet from / until"), "Show amounts". Esperado: se guardan al reabrir; error "We couldn't save the change" solo sin red.
- [ ] **8.5** Alertas de precio (Settings > "Price alerts", `/alerts`): crear una alerta cerca del precio actual. Free: bloqueo claro (es una función de pago); Premium/Gold: crear, editar, borrar.
- [ ] **8.6** Android: Ajustes del sistema > Apps > Porty > Notificaciones: anotar los nombres de los canales y en qué idioma están (ver Riesgos). Android 13+: el permiso se pide con el diálogo del sistema.
- [ ] **8.7** Cambiar el idioma de la app a español, mandar otra "de prueba": la push llega en español.

---

## 9. Cambio de idioma y de tema (4 min)

- [ ] ⛔ **9.1** Settings > Preferences / Preferencias > "Language" / "Idioma": hoja con "Español" y "English". Elegir "Español". Esperado: **toda** la app cambia en el momento (Settings, pestañas "Inicio / Porty / Metas / Ajustes", Home, paywall), sin reiniciar. Volver a "English" y verificar lo mismo.
- [ ] **9.2** Cerrar la app del todo y reabrir. Esperado: recuerda el idioma elegido (la pantalla de carga puede usar el del teléfono; es normal).
- [ ] ⛔ **9.3** Teléfono en español, app recién instalada: arranca en español, nombre "Porty" en el ícono. Teléfono en inglés: arranca en inglés (ya probado en 1.1).
- [ ] **9.4** Teléfono en **otro idioma** (por ejemplo Português o Deutsch): anotar en qué idioma arranca la app (hoy cae al español; ver Riesgos).
- [ ] **9.5** Recorrer en español: login, onboarding, Home, un detalle de posición, chat, Metas, Settings, paywall, notificaciones. Buscar mezclas de idioma y textos cortados (el español es más largo).
- [ ] ⛔ **9.6 Tema.** Settings > "Appearance" / "Apariencia": "System / Sistema", "Light / Claro", "Dark / Oscuro". Probar cada uno. Esperado: cambia al instante; en oscuro, texto legible en Home, chat y cards, paywall (Gold tiene tema propio) y gráfico; ningún texto negro sobre fondo oscuro ni al revés.
- [ ] **9.7** Con tema "System", cambiar el modo oscuro del teléfono con la app abierta: sigue al sistema.
- [ ] **9.8** Formatos: anotar cómo salen montos y fechas en cada idioma (hoy son los mismos en ambos: "$2,058.00" y "Nov 5, 2026"). No es bug por sí mismo, pero decidir si molesta al usuario uruguayo (ver Riesgos).

---

## 10. Sin red, errores y estados vacíos (5 min)

- [ ] ⛔ **10.1 Arranque sin red** (modo avión, app ya logueada). Esperado: la app abre (sesión local) y muestra un estado de error recuperable con "Retry" / "Reintentar" o los datos guardados; no se queda cargando para siempre ni crashea.
- [ ] ⛔ **10.2 Sin red en el login.** Intentar entrar: "No connection. Check your internet and try again." / "No hay conexión. Revisá tu internet…".
- [ ] **10.3 Sin red en el chat.** Mandar una pregunta: aparece un banner de error con "Retry" y el texto que escribiste no se pierde; al volver la red y reintentar, responde.
- [ ] **10.4** Red lenta/perdida a mitad de una respuesta del chat: no queda "Porty is generating…" infinito (debe haber un timeout con mensaje).
- [ ] **10.5** Home sin red con datos viejos: banner de error de cotizaciones con "Retry"; los valores no se ponen en 0.
- [ ] **10.6** Cuenta recién creada, sin nada: Home muestra "No positions yet. Add your first investment." con "Add position" y "Import from a file"; Goals muestra su vacío (6.1); chat muestra "Add open or closed positions…"; "Closed positions" muestra "You haven't closed any position yet"; el informe semanal no aparece.
- [ ] **10.7** Sesión vencida: (si podés, cerrar sesión desde otro dispositivo o esperar) Esperado: "Your session expired. Please sign in again." y vuelve al login, sin pantalla de error genérica.
- [ ] **10.8** Ruta inexistente / error de página: si aparece una pantalla de error genérica, debe tener texto en el idioma de la app y salida a Home ("An error occurred" / "Ocurrió un error").
- [ ] **10.9** Actualización obligatoria: (informativo) existe una pantalla bloqueante de "actualizar app" desde el servidor; confirmar con `porty-devops-release` que NO está activada para esta versión (si lo estuviera, nadie podría usar la app).
- [ ] **10.10** Texto grande: iPhone Ajustes > Accesibilidad > Texto más grande al máximo; Android > Tamaño de fuente al máximo. Recorrer Login, Home, chat, paywall, Settings. Esperado: se puede leer y tocar todo; nada cortado detrás del teclado ni botones inalcanzables.
- [ ] **10.11** Lector de pantalla (VoiceOver / TalkBack) 1 minuto: login y Home: los botones se anuncian con nombre ("Sign in", "Show password", "Open Porty"), no "botón sin etiqueta".

---

## 11. Borrado de cuenta (3 min) ⛔

Hacelo al final, con la cuenta que usó la compra de sandbox (así probás el aviso de suscripción activa).

- [ ] ⛔ **11.1** Settings > sección "Account" / "Cuenta" > "Delete account" / "Eliminar cuenta". Esperado: hoja "Delete your account?" / "¿Eliminar tu cuenta?" explicando que se borran cartera, conexiones, metas, alertas y plan. Con suscripción activa: aviso "You have an active subscription on App Store / Google Play. Deleting your account doesn't cancel it." y botón "Manage subscription on <tienda>" que abre la tienda.
- [ ] ⛔ **11.2** Confirmar. Esperado: "Deleting your account…", luego vuelve al login con el mensaje "Your account has been deleted…". En iPhone con Apple: mensaje adicional para quitar el acceso de Apple (`..._done_apple`).
- [ ] ⛔ **11.3** Volver a entrar con el mismo mail (o crear de nuevo): empieza de cero (sin posiciones, sin metas, plan Free, onboarding de nuevo). No debe aparecer nada de la cuenta anterior.
- [ ] **11.4** Sin red al borrar: "We couldn't delete your account, and nothing was deleted. Try again." (no queda a medias).
- [ ] ⛔ **11.5** Abrir en el navegador del teléfono la página pública `https://portyassistant.com/borrar-cuenta` (la que pide Google Play) y verificar que carga, explica los pasos y muestra `soporte@portyassistant.com`. Escribir a ese mail un "test" y confirmar que llega (alguien lo lee).
- [ ] **11.6** En Supabase (o pidiéndoselo a `porty-backend-dev`), confirmar que el usuario ya no existe y que se borraron sus filas (posiciones, metas, `weekly_reports`).

---

## 12. iPhone chico (SE / 375 pt) (3 min)

Si no tenés un SE, usá el simulador o decile al dev que corra la captura; en el teléfono grande probá además con texto grande (10.10), que es equivalente.

- [ ] **12.1** Login y onboarding sin overflow (no aparecen franjas amarillas/rojas ni texto pisado); el botón principal es alcanzable con el teclado abierto.
- [ ] **12.2** Home: total, rangos (los 6 chips caben o se pueden scrollear), filas de posiciones con tickers y montos largos ("$1,234,567.89"); el % no se corta.
- [ ] **12.3** Chat con teclado abierto: el campo de texto se ve, las cards no se salen de pantalla, las cards anchas (comparación, plan de ahorro) se ven completas.
- [ ] **12.4** Paywall con los dos planes: scrolleable, botones visibles, texto legal accesible. En español (más largo) y en texto grande.
- [ ] **12.5** Swipe lateral entre pestañas (Home > Porty > Metas > Ajustes) funciona y no choca con el gráfico de Home ni con el scrub.

---

## 13. Android (4 min)

- [ ] ⛔ **13.1** Instalar desde la pista interna/APK de release. Abre, login por email y por Google; "Continue with Apple" no aparece.
- [ ] **13.2** Botón/gesto "atrás": desde el detalle de posición vuelve a Home; desde una pestaña raíz no cierra la app inesperadamente ni deja una pantalla negra; desde el paywall cierra la hoja.
- [ ] **13.3** Barra de estado y navegación en oscuro/claro: sin texto invisible.
- [ ] **13.4** Compra con cuenta de licencia de prueba (7.3 en Android): la hoja de Google Play dice "Test card, always approves"; el plan se activa. "Restore purchases" funciona.
- [ ] **13.5** Link de confirmación de mail y de reset de contraseña se abre en la app (no en el navegador sin volver). Si el navegador pregunta "¿abrir con?", elegir Porty.
- [ ] **13.6** Notificación de prueba llega con ícono de Porty (no el cuadrado blanco) y en el canal correcto.
- [ ] **13.7** Importar archivo/captura: el selector de archivos de Android encuentra el CSV/PDF/imagen y vuelve a la app sin crash.
- [ ] **13.8** Ficha de Play: confirmar que existe la política de privacidad vigente y la URL de borrado de cuenta (11.5), requisitos de Google Play.

---

## 14. Cierre

- [ ] ⛔ **14.1** Hubo algún crash o pantalla blanca en toda la prueba. Si sí: NO publicar; anotar pasos exactos.
- [ ] ⛔ **14.2** En el idioma inglés no vi ninguna palabra en español en ninguna pantalla (incluidas cards del chat, informe semanal, paywall, notificaciones).
- [ ] **14.3** Anotar la versión/build probado (Settings > "Version" / "Versión"): ______ y el dispositivo: ______

Resultado: ______ (pasa / pasa con bugs menores / no pasa) · Bloqueantes fallados: ______ · Bugs anotados: ______

---

## Riesgos encontrados (lectura de código, sin ejecutar)

Ordenados por impacto para un lanzamiento mundial con foco en usuarios en inglés. No se corrigió nada. Ninguno se verificó en dispositivo: confirmalo con los pasos indicados.

1. **Alto. Permisos de iOS solo en español, sin localización.** `ios/Runner/Info.plist:44-47`: `NSMicrophoneUsageDescription` ("Porty usa el micrófono para que le dictes tus preguntas en el chat.") y `NSSpeechRecognitionUsageDescription` están en español fijo y no hay `InfoPlist.strings` ni `CFBundleLocalizations` en `ios/`. Un revisor de App Store o un usuario de Product Hunt con iPhone en inglés ve el diálogo del micrófono en español, y puede generar rechazo de revisión. Verificar en 4.12. Dueño probable: `porty-flutter-dev` (más `porty-devops-release` para el proyecto de Xcode).
2. **Alto (decisión de producto). Idioma por defecto es español para cualquier idioma no soportado.** `lib/main.dart:99` (`fallbackLocale: Locale('es','ES')`) y `lib/presentation/shared/loading/app_bootstrap.dart:119-132` (`_copy` cae a español si el idioma no es `en`). Un usuario con teléfono en alemán, francés o portugués ve la app en español, cuando para un lanzamiento mundial lo esperable es inglés. Verificar en 9.4. Dueño: `porty-flutter-dev` / `porty-product-owner`.
3. **Medio. Fechas y montos con formato estadounidense en ambos idiomas.** `lib/presentation/shared/formatting/app_number_format.dart:12-37` no pasa locale (comentario del propio archivo: sale "$2,058.00" también en español) y `DateFormat.yMMMd()` / `yMMMM()` / `MMMd()` sin locale en `lib/presentation/flows/home/ui/widgets/portfolio_hero_section.dart:111`, `lib/presentation/flows/position/ui/widgets/position_date_field.dart:56`, `lib/presentation/flows/position/ui/position_detail_screen.dart:673`, `closed_position_detail_screen.dart:219,315`, `close_position_screen.dart:689`, `closed_positions_screen.dart:153,403`. Un usuario en español ve "Nov 5, 2026" y "$2,058.00", mientras `es-ES.json:186` dice "$10.000" (`assistant_chip_goal`): inconsistente dentro de la misma app. No afecta al usuario en inglés. Verificar en 3.3 y 9.8.
4. **Medio. El informe semanal queda en el idioma en que se generó.** `lib/features/weekly_report/providers/weekly_report_controller.dart:294` genera una sola vez por usuario y semana (PK `(user_id, week_start)` en `supabase/migrations/20261002120000_weekly_reports.sql:14-28`) y el payload no guarda idioma. Si el usuario cambia de idioma después de generado, el texto de Porty queda en el idioma anterior hasta el sábado siguiente. Verificar en 5.6. Dueño: `porty-flutter-dev` / `porty-backend-dev`.
5. **Medio. Canales de notificación de Android en español.** `lib/features/notifications/data/push_messaging.dart:80,85,90,95` ("Alertas de precio", "Tu cartera", "Informes", "Cuenta"). Se ven en Ajustes del sistema > Notificaciones de Porty aunque la app esté en inglés. Verificar en 8.6.
6. **Bajo. Texto fijo en español en la card de error.** `lib/shared/widgets/genui_error_card.dart:31` ("No se pudo renderizar este componente."), usada por `lib/features/genui_core/widgets/guarded_catalog_widget.dart:17` cuando falla cualquier card del chat. Solo se ve si una card falla, pero un usuario en inglés vería español justo en el momento del error.
7. **Bajo. Links legales sin versión en inglés confirmada.** `lib/config/legal/legal_links.dart:3-9` apunta a `/app/terminos`, `/app/privacidad`, `/borrar-cuenta`, y el código no pasa idioma. Confirmar que el sitio muestra inglés (1.4, 11.5): Apple y Google revisan estas páginas y el público de Product Hunt las lee.
8. **Bajo. Mails de Supabase Auth (confirmación y reset) probablemente en un solo idioma.** No hay plantilla por idioma en el repo que yo haya visto; el primer mail que recibe un usuario en inglés es el de confirmación. Verificar en 1.7 y, si está en español, decidirlo con `porty-backend-dev`.
9. **Bajo (producto). Monedas de visualización orientadas a Latinoamérica.** `lib/features/display_currency/domain/display_currency.dart:7-16`: USD, UYU, ARS, BRL, MXN, CLP, COP, PEN, EUR, GBP; faltan CAD, AUD, JPY, CHF, INR, útiles para el público en inglés. No rompe nada.
10. **Bajo. Pulido del español.** `assets/translations/es-ES.json:236` ("Reintente mas tarde": sin tilde y en "usted", el resto de la app usa voseo) y `:216` ("Ayúdame a invertir": sin voseo, debería ser "Ayudame").
