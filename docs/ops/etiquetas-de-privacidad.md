# Etiquetas de privacidad de las tiendas

Respuestas para completar **App Store Connect → App Privacy** y **Play Console → Data safety**. Tienen que coincidir con `ios/Runner/PrivacyInfo.xcprivacy` y con la política `portyassistant.com/app/privacidad` (repo porty-web, `src/pages/app/privacidad.astro`). Si cambia algo de lo que la app guarda o manda, se actualizan los tres juntos.

Actualizado: 2026-11-06 (incluye el widget de la pantalla de inicio).

## Lo que NO se declara

- **El resumen que guarda el widget** (valor, variación, ticker, titulares, fechas de resultados): queda en el teléfono y no sale de él. Apple y Google solo cuentan como "recopilado" lo que se transmite fuera del dispositivo.
- **Seguimiento (tracking):** no. No hay publicidad de terceros ni se cruzan datos con otras empresas para anuncios.
- **Datos de pago:** los procesan Apple y Google; Porty no los recibe.

## App Store Connect → App Privacy

1. "Do you or your third-party partners collect data from this app?" → **Yes**.
2. Marcar estos tipos. Para cada uno: **Linked to the user: Yes** · **Used for tracking: No**.

| Categoría | Tipo | Propósitos |
|---|---|---|
| Contact Info | Email Address | App Functionality |
| Contact Info | Name | App Functionality |
| Identifiers | User ID | App Functionality |
| Identifiers | Device ID | App Functionality (token de notificaciones push) |
| Financial Info | Other Financial Info | App Functionality (cartera, posiciones, operaciones, conexiones con brókers) |
| User Content | Other User Content | App Functionality (mensajes del chat con Porty) |
| Purchases | Purchase History | App Functionality, Analytics |
| Usage Data | Product Interaction | Analytics (eventos de uso, incluidos los del widget) |

3. **Privacy Policy URL:** `https://portyassistant.com/app/privacidad`.

## Play Console → Data safety

- "Does your app collect or share any of the required user data types?" → **Yes**.
- "Is all of the user data collected by your app encrypted in transit?" → **Yes** (todo va por HTTPS).
- "Do you provide a way for users to request that their data is deleted?" → **Yes**: en la app (Ajustes → Eliminar cuenta) y en `https://portyassistant.com/borrar-cuenta`.

Para cada tipo: **Collected: Yes** · **Shared: No** (Supabase, OpenAI, RevenueCat, Firebase y los brókers procesan por cuenta de Porty; Google no lo cuenta como "compartir") · **Processed ephemerally: No** · **Required** salvo donde se indica.

| Sección | Tipo | Opcional | Propósitos |
|---|---|---|---|
| Personal info | Email address | Requerido | App functionality, Account management |
| Personal info | Name | Opcional | App functionality, Account management |
| Personal info | User IDs | Requerido | App functionality, Account management |
| Financial info | Other financial info | Requerido | App functionality |
| Financial info | Purchase history | Opcional | App functionality, Analytics |
| Messages | Other in-app messages | Opcional | App functionality (chat con Porty, se envía a OpenAI para responder) |
| App activity | App interactions | Requerido | Analytics |
| Device or other IDs | Device or other IDs | Opcional | App functionality (token de notificaciones) |

## Pendiente de confirmar antes de enviar

- **Errores o diagnósticos:** la política dice que se registran "errores". Si la app manda errores al servidor (o si se suma Crashlytics o Sentry), agregar en Apple **Diagnostics → Other Diagnostic Data** (App Functionality) y en Google **App info and performance → Diagnostics**, y en `PrivacyInfo.xcprivacy`.
- **Revisión del abogado** de la política y de estas respuestas (B15 del checklist del release 1).
