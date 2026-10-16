# Borrador: alta como proveedor externo en IBKR (Web API, OAuth 1.0a)

**Estado:** BORRADOR. No se envió. Lo revisa y lo manda Alfonso.
**Firma:** Alfonso Katzenstein, Founder de Porty

## Antes de enviar

- [ ] Confirmar el correo de destino. La documentación de IBKR da dos:
      `webapionboarding@interactivebrokers.com` (página "Trading Access for Third Parties") y
      `api-solutions@interactivebrokers.com` (página "Registration Process"). Mandarlo al primero con
      copia al segundo, o preguntar en uno cuál corresponde.
- [ ] Completar los `<…>` (razón social, país, email de contacto).
- [ ] Ver si ya cumplimos lo que IBKR espera de entrada:
  - empresa constituida (como persona física no aplica);
  - sitio público que describa Porty y sus funciones (https://portfolioai.app tiene que estar
    completo, porque Compliance lo revisa);
  - prueba de concepto. Mostrar la integración con eToro y, si llegamos a tiempo, una versión con
    IBKR Flex Web Service.
- [ ] Pedir **solo lectura**. Si más adelante sumamos órdenes, IBKR exige una nueva aprobación de
      Compliance.

Plazos según IBKR: revisión inicial de 2 a 3 semanas, Compliance de 3 a 6 semanas, y después
contrato y configuración. En total, entre 5 y 11 semanas.

---

## Correo (en inglés)

**To:** webapionboarding@interactivebrokers.com
**Cc:** api-solutions@interactivebrokers.com
**Subject:** Third-party Web API access request (OAuth 1.0a, read-only): Porty

Hello IBKR API Solutions team,

I'm Alfonso Katzenstein, founder of Porty (https://portfolioai.app), a mobile portfolio tracking
app with an AI assistant for retail investors.

We would like to apply for third-party access to the IBKR Web API using OAuth 1.0a, so that IBKR
clients can connect their account to Porty and see their portfolio there.

- **Read-only.** Porty would only read positions, trades, balances and account summary. We do
  not place, modify or cancel orders, and we are not requesting trading access.
- **Data use.** Each user's data is shown only to that same user, including when they ask
  Porty's AI assistant about their own portfolio. We never sell or share it.
- **Security.** Access tokens are stored encrypted on our server and are revoked and deleted as
  soon as the user disconnects.
- **Existing integration.** We have already built and tested a similar read-only OAuth
  integration with eToro, and we're happy to demo it as a proof of concept.

Could you please send us the third-party onboarding questionnaire and let us know the next steps?
We're glad to provide a demo, documentation or anything else Compliance needs.

Best regards,

Alfonso Katzenstein
Founder, Porty
<legal entity name>, <country>
<contact email>

---

## Respuestas preparadas para el cuestionario

El cuestionario real lo manda IBKR. Estas son respuestas a las preguntas que más probablemente
haga, según lo que su documentación dice que revisa. Están en inglés para copiarlas tal cual.

### Company

| Field | Answer |
|---|---|
| Legal entity name | `<…>` |
| Country of incorporation | `<…>` |
| Year founded | `<…>` |
| Website | https://portfolioai.app |
| Primary contact | Alfonso Katzenstein, Founder, `<email>` |
| Regulatory registration | None. Porty does not provide investment advice, execute trades or hold client assets; it is a read-only portfolio tracking tool. `<Confirmar con un abogado si hace falta algo en los países donde operamos.>` |
| Other broker integrations | eToro (read-only OAuth, built and tested, pending eToro's approval) `<actualizar si ya la aprobaron>` |

### Product

- **Description:** Porty is a mobile app (iOS and Android) for casual retail investors. It shows
  the user's portfolio (total value, P&L, positions, charts) and includes an AI assistant that
  answers questions about the user's own portfolio and the market.
- **Target users:** individual retail investors (stocks and ETFs). Not professional traders.
- **Markets served:** `<países>`
- **Business model:** paid subscription to Porty (Free / Premium / Gold plans). We do not charge
  per trade, take commissions or receive payment for order flow.
- **Number of users:** `<…>`

### Requested access

- **Authentication:** OAuth 1.0a (third-party).
- **Scope:** read-only. Account summary, positions, trade history, cash balances.
- **Trading:** none. No orders, no account changes, no transfers.
- **Data refresh:** on user request and a periodic background sync (`<frecuencia>`).
- **Callback URL:** `<https://<project>.supabase.co/functions/v1/ibkr-sync/callback>` (to be
  confirmed when we build it).
- **Public keys:** we will provide the signature and encryption keys when onboarding asks for
  them.

### Data handling and security

- **What we store:** positions, trades and balances needed to show the portfolio. We don't
  store the user's IBKR credentials. We never see them because login happens on IBKR's side.
- **Token storage:** encrypted on our server (Supabase Vault), never on the device.
- **Access control:** each user can only read their own data (row-level security). Broker-synced
  rows are read-only for the app.
- **AI assistant:** the user's own portfolio data is sent to our AI provider only to answer
  that user's questions. It is not used to train models and never shown to other users.
  `<Confirmar los términos del proveedor de IA antes de enviar.>`
- **Revocation and retention:** when the user disconnects, we revoke the token and delete it
  immediately. The user chooses whether to keep imported positions as manual entries or delete
  them. Deleting the Porty account deletes everything.
- **Data sharing:** none. We don't sell or share user data with third parties.

### Proof of concept

- Live demo of the eToro read-only integration (connect, import, disconnect).
- `<Si llegamos a tiempo: demo de IBKR con Flex Web Service.>`
- Screenshots and video available on request.

## Fuentes

- [Registration Process – IBKR Web API](https://www.interactivebrokers.com/docs/web-api/authentication/oauth-1a/third-party-oauth/registration-process)
- [Trading Access for Third Parties](https://www.interactivebrokers.com/docs/web-api/trading/getting-started/trading-access-for-third-parties)
- [Third Party OAuth Workflow](https://www.interactivebrokers.com/docs/web-api/authentication/oauth-1a/third-party-oauth/third-party-o-auth-workflow)
- Seguridad y retención de eToro, usadas como base: `docs/runbooks/etoro-sync.md`
