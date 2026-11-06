---
name: widget-news-licensing-and-apple-4-4
description: 2026-11-05 review of widget news/earnings expansion - Finnhub free not usable commercially, v2 earnings dates are estimates, Apple 4.4 vs plan teasers in widgets
metadata:
  type: project
---

Reviewed docs/specs/home-widget-product.md ampliación (verdict: bloquea).

- Finnhub ToS (finnhub.io/terms-of-service): no redistribution of data or derived results, plans personal-only unless stated. Project already moved news/earnings to v2 (GDELT + SEC, docs/runbooks/news-sources-v2.md). Spec A1 still pointed at legacy Finnhub entities.
- v2 earnings dates are ESTIMATES (no calendar, no bmo/amc) -> never word as "presenta resultados el jueves"; v2 edge functions 403 non-Gold.
- Apple 4.4 + DPLA 3.3.7(E) (unverified PDF): extensions may not carry marketing/product promotion/IAP offers -> "· Premium" teaser in iOS widget is high risk; Android low-medium.
- User decision: "Ocultar montos" hides amounts only; tickers/headlines stay visible. Do not revert; require .privacySensitive() + clarifying Settings text.

**How to apply:** future widget/teaser/news-source reviews; check whether the source is licensed first.
