# Borrador: contacto con SnapTrade

**Para:** api@snaptrade.com (o el chat de https://dashboard.snaptrade.com, con la cuenta que cree
el client ID de Porty).
**Firma:** Alfonso Katzenstein, Founder de Porty
**Estado:** BORRADOR. No se envió. Lo revisa y lo manda Alfonso.

Contexto: la integración `snaptrade-sync` (ver `docs/runbooks/snaptrade-sync.md`) ya está escrita
y probada con tests, sin claves reales. Antes de lanzarla hay que confirmar precios y tres
detalles técnicos.

Lo que ya sabemos por el SDK oficial (`snaptrade-typescript-sdk` 13.1.14) y conviene que confirmen:

- El plan (Daily o Real-time) va **por clave de API**: "Check your API key on the Customer
  Dashboard billing page to see whether your plan includes real-time data".
- La actualización manual (`POST /authorizations/{id}/refresh`) existe en Daily, **se cobra
  aparte en cada llamada**, y está deshabilitada en Real-time.
- El Connection Portal solo viene en `en` y `pt-BR`: no hay español.

---

**Subject:** Porty: pricing and setup questions before launching SnapTrade

Hello SnapTrade team,

I'm Alfonso Katzenstein, founder of Porty (https://portfolioai.app), a portfolio tracking app with
an AI assistant for casual investors, mostly in Uruguay and Argentina.

We've built a **read-only** SnapTrade integration (connectionType `read`, never `trade`) so our
paid users can connect brokers we don't support directly, such as Interactive Brokers or Schwab.
Before launching, we'd like to confirm a few things:

1. **Plans by user tier.** We'd like our Premium users on Pay as you go / Daily ($1/user/month)
   and, possibly, our Gold users on Real-time ($2/user/month). Can one client ID mix both plans per
   user, or do we need two separate API keys? Does a user registered under one key have to
   reconnect their broker if we move them to the other?
2. **Manual refresh.** On the Daily plan, how much does each call to
   `POST /authorizations/{id}/refresh` cost? We'd offer it only to Gold users, with a daily cap.
3. **Billing when a user leaves.** If a user connects and we delete them
   (`DELETE /snapTrade/deleteUser`) in the same month, is that a full month? Is a registered
   user with no active connection billed?
4. **Mobile redirect.** Can `customRedirect` be a custom URL scheme
   (`porty-snaptrade://callback`) for our iOS/Android app, used together with
   `immediateRedirect: true`?
5. **Coverage for our users.** Our users live mainly in Uruguay and Argentina. Is there any
   restriction on connecting accounts for residents of those countries? Which brokerages can
   they typically connect (for example IBKR, Schwab, Webull, Public)?
6. **Language.** Is a Spanish version of the Connection Portal on your roadmap?
7. **Data use.** Users will be able to ask our AI assistant about their own connected portfolio.
   The data is shown only to that same user, never shared or sold. Is that compatible with your
   developer terms?

Happy to share more details or a demo build if that helps.

Thanks,
Alfonso Katzenstein
Founder, Porty
[email de contacto]
