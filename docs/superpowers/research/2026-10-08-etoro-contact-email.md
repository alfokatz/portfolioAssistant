# Borrador: contacto con eToro

**Para:** equipo de partnerships de eToro (vía el formulario de registro de apps en
builders.etoro.com/app-registration) y `apisupport@etoro.com`
**Firma:** Alfonso Katzenstein, Founder de Porty
**Estado:** BORRADOR. No se envió. Lo revisa y lo manda Alfonso.

Antes de enviarlo, completar el email de contacto al pie.
Actualizado el 2026-10-09: la app OAuth ya está creada (client ID `6419e1a0-56b2-41e9-8ec3-ba89cacad020`)
y la conexión se probó de punta a punta en modo demo.

---

**Subject:** Partner / OAuth app registration request — Porty (read-only portfolio sync)

Hello eToro Builders team,

I'm Alfonso Katzenstein, founder of **Porty** (https://portfolioai.app), a mobile app (iOS and
Android) that helps retail investors track their portfolio and understand it with an AI assistant.
Porty is a paid subscription app.

We would like to let eToro users **connect their eToro account to Porty so their portfolio is
mirrored automatically**, instead of entering positions by hand. The integration is **strictly
read-only**: Porty never places, modifies or closes orders, and we will reject any token that
carries a write scope.

**What we're requesting**

1. Review and **approval for production** of Porty's OAuth (SSO) client, which we have already
   created in the self-service dashboard (client ID `6419e1a0-56b2-41e9-8ec3-ba89cacad020`). It uses
   the authorization code flow with PKCE and a confidential backend that exchanges the code and
   stores the tokens. We have already tested the full flow end to end with a demo account.
   - Redirect URI (HTTPS, server-side): `https://rungwxgkwxtekijbynkm.supabase.co/functions/v1/etoro-sync/callback`.
     Our backend then returns the user to the app. No tokens ever reach the device.
   - Requested scopes: `openid` and `etoro-public:real:read` (plus `etoro-public:demo:read` for
     testing). That is enough for `/api/v1/me`, `/trading/info/real/pnl` and
     `/trading/info/trade/history` per your OpenAPI v1.387.0. **No write scopes.**
2. **Written authorization for commercial use**: Porty would offer this feature to its own users
   (eToro account holders who opt in), as part of a paid subscription, outside the eToro App Store.
   We understand from the Builders' Economy Terms (17 Feb 2026) that "Permitted Use" excludes
   commercial redistribution and use on behalf of third parties unless expressly authorized, so
   we'd like to do this properly under whatever partner agreement applies.

**How we'd use the data**

- Endpoints: `GET /api/v1/me`, `GET /api/v1/trading/info/real/pnl` (or `/portfolio`),
  `GET /api/v1/trading/info/trade/history`, and `GET /api/v1/market-data/instruments`
  (plus the instrument types and exchanges catalogs).
- About 5 requests per sync. Syncs happen when the user connects, when they open the app (at most
  every 15 minutes) and on pull-to-refresh, with a server-side minimum of 5 minutes between syncs.
  We cache instrument metadata.
- Tokens are encrypted at rest (Supabase Vault), refresh-token rotation is persisted atomically,
  tokens are never logged, and they are revoked and deleted when the user disconnects.
- The positions are shown only to the account owner inside Porty. They are also included in the
  context of Porty's AI assistant so the user can ask questions about their own portfolio. The AI
  provider (OpenAI) processes that data on our behalf, only to answer that user.

**Questions**

1. Is the above eligible for OAuth registration? Does an approved OAuth client constitute the
   "express written authorisation" referred to in Part I §1.2 and Part V §1.5 of the Builders'
   Economy Terms, or is a separate partner agreement required? What review steps and timeline
   should we expect?
2. Is charging a subscription that includes this feature acceptable, or does it require eToro's
   prior consent under the App Store fee provisions?
3. Does "Licensed Content" (Part II §3: "charts, volumes, sentiments, news, and related
   information") include a user's own positions and trade history? Is it acceptable to store them in
   our database while the account is connected (Part V §1.8), and to include them in our AI
   assistant's context to answer that same user (Part V §1.7 mentions "ground any model")? Are there
   retention, deletion or attribution ("eToro's marks") requirements?
4. Can we be sure the consent screen grants **only** the read scopes we request? Will
   `/api/v1/me` reliably return the granted scopes?
5. Your docs say the access token is bound to the user's interactive session and that backend work
   without the user present (e.g. "portfolio synchronization") requires a non-interactive token.
   Porty syncs when the user opens our app or pulls to refresh (they're present in Porty, not in an
   eToro session). Is the refresh token enough for that, or should we issue a NIT
   (read-only, `etoro-public:trade.real:read`, with `expiresAt`)? Our backend runs on Supabase Edge
   Functions with no fixed egress IP, so we can't set `ipsWhitelist`. Is that acceptable? Do
   refresh tokens rotate on every refresh, and what is their actual lifetime?
6. Closed-trade history: is the current path `/api/v1/trading/info/trade/history` (with
   `minDate`, `page`, `pageSize`) or `/trading/info/real/history`? Does it work with demo
   credentials? Is there a way to know a closed trade's settlement type (CFD vs. real asset) and
   whether it came from copy trading?
7. Is the rate limit for these read endpoints 60 requests/minute per user, and is the trade-history
   endpoint in the 20/minute bucket?
8. Our application is currently "InDev". What do we need to do to move it to "Approved" so that
   any eToro user can connect, and is a demo account enough for your reviewers to test it?
9. Any security, branding ("Connect with eToro") or disclosure requirements we should follow?

Happy to share a demo video, staging access, our privacy policy and a security overview.

Best regards,

Alfonso Katzenstein
Founder, Porty
https://portfolioai.app
<email de contacto>
