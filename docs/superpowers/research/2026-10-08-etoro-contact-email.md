# Borrador: contacto con eToro

**Para:** `apisupport@etoro.com`
**Firma:** Alfonso Katzenstein, Founder de Porty
**Estado:** BORRADOR. No se envió. Lo revisa y lo manda Alfonso.

Antes de enviarlo, completar el email de contacto al pie.

Actualizado el 2026-10-09:
- la app OAuth ya está creada (client ID `6419e1a0-56b2-41e9-8ec3-ba89cacad020`);
- la conexión se probó de punta a punta en modo demo;
- el tono ahora es "ya estamos integrados, pedimos confirmación".

---

**Subject:** Porty: read-only OAuth integration ready, requesting confirmation for production use

Hello eToro Builders team,

I'm Alfonso Katzenstein, founder of **Porty** (https://portfolioai.app). Porty is a mobile app for
iOS and Android that helps retail investors track their portfolio and understand it with an AI
assistant.

**We have already integrated Porty with eToro**, following your SSO / OAuth documentation:

- We registered our OAuth application in the Builders self-service dashboard.
  - Client ID: `6419e1a0-56b2-41e9-8ec3-ba89cacad020`.
  - Redirect URI: `https://rungwxgkwxtekijbynkm.supabase.co/functions/v1/etoro-sync/callback`.
- We tested the full flow end to end with a demo account.

With it, eToro users can connect their account and see their portfolio in Porty automatically
instead of typing it in by hand.

Before we make it available to our users, we'd like to **confirm with you that we can use it with
Porty**, and to move the application from "InDev" to "Approved". Porty is a subscription app and
the feature would be offered outside the eToro App Store. Your Builders' Economy Terms
(17 Feb 2026, Part I §1.2 and Part V §1.5) mention express authorisation for use on behalf of
third parties, so we want to make sure we do this properly.

**How the integration works**

- **Strictly read-only.** We only request `openid` and `etoro-public:real:read`
  (plus `etoro-public:demo:read` for testing).
  - Porty never places, modifies or closes orders and never moves funds.
  - If a token ever arrives with a write scope, our backend revokes it and rejects the connection.
- **Standard, secure OAuth.** We use the authorization code flow with PKCE (S256).
  - A confidential backend exchanges the code, and the ID token is validated (signature, `iss`,
    `aud`, `nonce`).
  - The user signs in on eToro's own page in the system browser. Porty never sees their eToro
    password.
- **Minimal API usage.** Each sync makes about 5 GET requests:
  - Endpoints: `/api/v1/me`, `/api/v1/trading/info/real/pnl`, `/api/v1/trading/info/trade/history`
    and the instrument catalogs, which we cache for 24 hours.
  - When syncs happen: when the user opens the app (at most every 15 minutes) or pulls to refresh,
    with a server-side minimum of 5 minutes between syncs.

**How we handle data**

- **No sensitive personal information.**
  - Porty does not request or receive names, emails, phone numbers, addresses, ID documents or KYC
    data from eToro.
  - We identify the connection only by the pseudonymous `sub` from the ID token, as your
    documentation recommends.
- **We only use what the feature needs**: the user's open positions and closed trades, shown only
  to that same user inside Porty.
- **Porty never sells, shares or discloses this data.**
  - It is never used for advertising, never combined with other users' data and never made
    public.
  - The user's AI assistant can read their own portfolio to answer their own questions. Our AI
    provider processes that data on our behalf for that single purpose, and does not train on it.
- **Credentials are protected.**
  - Tokens are encrypted at rest (Supabase Vault) and live only on our server, never on the device.
  - They never appear in logs and are never sent to the AI provider.
- **The user stays in control.**
  - They can disconnect from Porty or from eToro at any time.
  - On disconnect we revoke the token with eToro and delete it immediately.
  - The imported positions are kept as manual entries or deleted, as the user chooses.
- We will notify you within 24 hours of any security incident, as your terms require.

**What we'd like to confirm**

1. That we can offer this integration to Porty users as described, and what we need to do to move
   the application to "Approved".
2. That showing users their own positions and trade history in Porty, including through their AI
   assistant, fits within your terms. Also, whether you have any requirements on data retention or
   on attribution and branding (e.g. "Connect with eToro").
3. That the OAuth refresh token is the right mechanism for syncs triggered when the user opens
   Porty, or whether you'd prefer a non-interactive token.

Happy to share a demo video, test access, our privacy policy or a security overview, whatever helps
your review.

Best regards,

Alfonso Katzenstein
Founder, Porty
https://portfolioai.app
<email de contacto>
