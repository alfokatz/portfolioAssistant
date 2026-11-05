# Brief: borrado de cuenta en la app

**Fecha:** 2026-11-02 · **Autor:** porty-product-owner · **Estado:** listo para porty-architect · **Condición para publicar el release 1** (`docs/product/roadmap.md`, ítem 0)

## 1. Problema

En Ajustes, "Eliminar cuenta" pide confirmación y después muestra "La eliminación de cuenta estará disponible pronto" (`lib/presentation/flows/settings/ui/settings_screen.dart:211-223`). En `supabase/` no hay ninguna función que borre usuarios. *Evidencia: lectura del código y `docs/legal/reviews/2026-11-02-paywall-y-nudges.md` H1.* Apple 5.1.1(v) exige borrado dentro de la app en toda app que permite crear cuenta, y Google Play exige borrado en la app más un link web. **Cualquier envío a las tiendas se rechaza**, sea cual sea su contenido. Para el usuario es también una cuestión de confianza: una app que guarda su cartera y no lo deja irse no es *trustworthy*.

## 2. Para quién

Todos los usuarios con cuenta (Free, Premium y Gold). El caso delicado es el usuario con suscripción activa.

## 3. Métrica de éxito

- El release 1 pasa la revisión de Apple y de Google sin rechazo por 5.1.1(v) ni por la política de borrado de Play.
- Al borrar una cuenta, no queda ninguna fila del usuario en las tablas con datos personales ni su cliente en RevenueCat. Lo verifica un test SQL o de integración.
- Para producto (no es meta): `account_deleted` como contador **sin user_id ni datos personales** (por ejemplo, un agregado por día y tier). Sirve como guardarraíl de la estrategia de paywalls. La forma exacta la define porty-architect con porty-security-reviewer.

## 4. Alcance mínimo

1. En la confirmación, antes de borrar: si tiene una suscripción activa, el aviso "Si tenés una suscripción activa, cancelala desde {store}: borrar tu cuenta no la cancela." con un link a la gestión de suscripciones de la tienda. **Texto final de porty-compliance.**
2. Edge function de borrado, con el JWT del propio usuario, en este orden: desconectar los brókers (borrar el usuario de SnapTrade, revocar los tokens de eToro, borrar las claves de Binance en Vault); borrar al cliente en RevenueCat (`DELETE /v1/subscribers/{app_user_id}`); borrar `auth.users`, que arrastra los datos por FK. Si un paso externo falla, no se borra `auth.users` y el usuario ve un error claro para reintentar.
3. Al terminar, la sesión se cierra y el usuario vuelve al login con un mensaje de confirmación.
4. Página web de borrado (la exige Google Play): puede ser un formulario simple o instrucciones con un mail de contacto. La crea el usuario o porty-marketing-lead en la landing.
5. El webhook de RevenueCat no tiene que fallar ni reintentar sin fin si llega un evento de un usuario borrado (compliance §3, condición 2).

**Textos y condiciones de compliance** (finales, en `docs/legal/reviews/2026-11-02-paywall-y-nudges.md` §6; se usan tal cual):
- El aviso de suscripción aparece con **cualquier** entitlement activo (`premium` o `gold`), aunque esté cancelado y le quede período. Si la tienda es `PROMOTIONAL` o desconocida, no aparece.
- `{store}` es la tienda donde se compró (`EntitlementInfo.store`), no la plataforma desde donde borra.
- El aviso va en la misma hoja y **antes** del botón de confirmar, con texto de peso normal: nada de esconderlo en un "más info".
- La lista de lo que se borra tiene que coincidir con las tablas que tienen `cascade`. Lo que se conserva (el contador agregado `account_deleted`, o `subscription_events` cuando pase a `set null`) no puede figurar como borrado.
- **Error (decisión de producto):** por defecto se usa el texto honesto de falla parcial ("No pudimos terminar de eliminar tu cuenta. Probá de nuevo; si sigue fallando, escribinos a {email}."). El texto "no se borró nada" solo se usa si porty-architect garantiza que un paso que falla no deja los brókers ya desconectados (por ejemplo, porque los pasos se pueden reintentar o deshacer). Preferimos un error un poco menos lindo antes que decirle al usuario algo que no es cierto.
- El plazo en que los datos desaparecen de los backups de Supabase va en la política de privacidad, no en la hoja (necesita revisión humana).

## Fuera de alcance

- Exportar datos antes de borrar.
- Período de gracia o "recuperar cuenta".
- Encuesta de por qué se va (después, y con compliance).
- Cancelar la suscripción desde la app: no se puede, es de la tienda.

## 5. Impacto en negocio

No aumenta los pagos. Es la condición para publicar cualquier cosa del mes (anual, paywall nuevo, sin callejones). Costo de no hacerlo: el mes entero sin release. Riesgo a cuidar: un usuario que borra la cuenta y sigue pagando, que es la peor reseña posible. Por eso el aviso del punto 1 no es opcional.

## 6. Criterios de aceptación de usuario

1. Desde Ajustes, el usuario puede borrar su cuenta sin salir de la app y sin escribirle a nadie.
2. Antes de confirmar, entiende qué se borra (cartera, conexiones, metas, alertas, planes e historial con Porty) y, si tiene un plan activo (aunque esté cancelado), que tiene que cancelarlo en la tienda donde lo compró, con el link a esa tienda.
3. Después de borrar, queda afuera de la app, y si vuelve a entrar con el mismo mail, empieza de cero.
4. Si algo falla, ve un error que dice la verdad sobre lo que quedó hecho, sabe cómo reintentar y tiene un mail de contacto. Su cartera y su cuenta siguen ahí.

## 7. Prioridad

No compite por RICE: es una condición para publicar. Va en paralelo con la apuesta #1 desde la semana 1 y define la fecha del release 1. Como le quita capacidad al backend, si hace falta la apuesta #5 (hábito del sábado) pasa de S3 a S4.

## 8. Decisión relacionada

`subscription_events.user_id`: **`on delete cascade` en este release.** Se pasa a `set null` cuando se cumplan las tres condiciones de compliance (§3): borrado en RevenueCat (lo trae este brief), webhook que tolere uuids borrados (punto 5) y el párrafo de Privacidad publicado (depende del usuario y de un abogado). Con el volumen actual, la pérdida analítica es despreciable.
