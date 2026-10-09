# Borrador: contacto con eToro

**Para:** `apisupport@etoro.com`
**Firma:** Alfonso Katzenstein, Founder de Porty
**Estado:** BORRADOR. No se envió. Lo revisa y lo manda Alfonso.

Antes de enviarlo, completar el email de contacto al pie.

Versión corta (2026-10-09):
- se dejó solo lo esencial: autorización comercial, aprobación de la app y uso de los datos en el
  asistente;
- los detalles técnicos y de seguridad se ofrecen al final si eToro los pide (ver
  `docs/runbooks/etoro-sync.md`).

---

**Subject:** Porty: confirmation to use our read-only eToro integration

Hello eToro Builders team,

I'm Alfonso Katzenstein, founder of Porty (https://portfolioai.app), a portfolio tracking app with
an AI assistant.

We've already integrated Porty with eToro through your OAuth flow (client ID
`6419e1a0-56b2-41e9-8ec3-ba89cacad020`) and tested it with a demo account. Users can connect
their eToro account and see their portfolio in Porty automatically.

- It's strictly **read-only** (`etoro-public:real:read`): Porty never trades or modifies anything.
- We don't receive any personal information, only the user's positions and trades. Those are shown
  only to that same user, including when they ask our AI assistant about their own portfolio.
- Porty never sells or shares this data, and tokens are stored encrypted on our server.

Before launching, we'd like to confirm two things:

1. Can we offer this to Porty users? Porty is a paid subscription app, outside the eToro App Store.
   If so, how do we move our app from "InDev" to "Approved"?
2. Is it OK for the user's AI assistant to use their own portfolio data to answer their questions?

Happy to share a demo or more technical details if useful.

Best regards,

Alfonso Katzenstein
Founder, Porty
<email de contacto>
