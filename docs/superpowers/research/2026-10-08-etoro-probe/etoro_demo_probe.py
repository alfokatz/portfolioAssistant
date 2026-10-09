#!/usr/bin/env python3
"""Prueba descartable: trae el portfolio DEMO de eToro y lo convierte al modelo de Porty.

NO es código de la app. Solo hace GET. Se niega a seguir si la clave tiene
algún scope de escritura o de la cuenta real.

Uso (claves por variable de entorno, nunca por argumento ni en archivos):
    ETORO_API_KEY=... ETORO_USER_KEY=... python3 -I etoro_demo_probe.py --live
    python3 -I etoro_demo_probe.py --fixtures <dir>   # sin red, con JSONs de ejemplo

Salida: JSON anonimizado (sin CIDs, usernames, ids de posición/orden).
"""
import argparse
import datetime as dt
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

BASE = "https://public-api.etoro.com"
USER_AGENT = "porty-etoro-probe/0.1"

# ---------------------------------------------------------------- transporte


class Api:
    """Cliente mínimo de solo lectura. No existe método para otro verbo HTTP."""

    def __init__(self, api_key, user_key):
        self._h = {"x-api-key": api_key, "x-user-key": user_key, "User-Agent": USER_AGENT}
        self.calls = []  # (path, status, ms, ratelimit-remaining)

    def get(self, path, params=None):
        q = ""
        if params:
            # eToro exige coma literal en listas (no %2C).
            q = "?" + "&".join(
                f"{k}={','.join(map(str, v)) if isinstance(v, (list, tuple)) else urllib.parse.quote(str(v))}"
                for k, v in params.items()
            )
        req = urllib.request.Request(BASE + path + q, method="GET",
                                     headers={**self._h, "x-request-id": str(uuid.uuid4())})
        t0 = time.monotonic()
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                body = r.read()
                self.calls.append((path, r.status, int((time.monotonic() - t0) * 1000),
                                   r.headers.get("X-RateLimit-Remaining")))
                return r.status, json.loads(body or b"null")
        except urllib.error.HTTPError as e:
            body = e.read()[:500].decode("utf-8", "replace")
            self.calls.append((path, e.code, int((time.monotonic() - t0) * 1000),
                               e.headers.get("X-RateLimit-Remaining")))
            return e.code, {"_error_body": body}


class Fixtures:
    """Mismo contrato que Api, leyendo los ejemplos de la spec oficial."""

    FILES = {
        "/api/v1/me": "getAuthenticatedUserProfile-response-200.json",
        "/api/v1/trading/info/demo/pnl": "getDemoAccountPnl-response-200.json",
        "/api/v1/trading/info/demo/aggregate-portfolio": "getAggregatedPortfolioDemo-response-200.json",
    }

    def __init__(self, d):
        self.d, self.calls = d, []

    def get(self, path, params=None):
        bundle = os.path.join(self.d, "bundle.json")
        if os.path.exists(bundle):
            b = json.load(open(bundle))
            st, body = b.get(path, [404, None])
            self.calls.append((path, st, 0, None))
            return st, body
        f = self.FILES.get(path)
        if not f or not os.path.exists(os.path.join(self.d, f)):
            self.calls.append((path, 404, 0, None))
            return 404, None
        ex = json.load(open(os.path.join(self.d, f)))["example"]
        if path == "/api/v1/me":  # el ejemplo viene envuelto en {example:{value}}
            ex = ex["example"]["value"]
            ex["scopes"] = ["etoro-public:demo:read"]  # simula una clave Read/Demo
        self.calls.append((path, 200, 0, None))
        return 200, ex


# ---------------------------------------------------------------- anonimizado

_SALT = os.urandom(8)


def anon(prefix, value):
    if value in (None, 0):
        return value
    return f"{prefix}_{hashlib.sha256(_SALT + str(value).encode()).hexdigest()[:6]}"


# ---------------------------------------------------------------- mapeo

SETTLEMENT = {0: "CFD", 1: "REAL_ASSET", 2: "SWAP", 3: "CRYPTO_MARGIN", 4: "FUTURE"}


def classify(pos, meta, types):
    """Devuelve (destino, motivo). destino ∈ import | separate | skip."""
    st = SETTLEMENT.get(pos.get("settlementTypeID"), f"UNKNOWN({pos.get('settlementTypeID')})")
    lev = pos.get("leverage") or 1
    kind = types.get((meta or {}).get("instrumentTypeID"), "desconocido")
    if (pos.get("mirrorID") or 0) > 0:
        return "separate", "copy_trading"  # mirror / Smart Portfolio
    if not pos.get("isBuy", True):
        return "skip", "short"
    if lev > 1:
        return "skip", "leveraged"
    if st != "REAL_ASSET":
        return "separate", f"not_owned_{st.lower()}"
    if meta is None:
        return "separate", "instrument_unresolved"
    k = kind.lower()
    if "stock" in k or "etf" in k:
        sym = meta.get("symbolFull", "")
        if "." in sym:  # BP.L, SAP.DE...: Porty hoy no cotiza fuera de EE.UU.
            return "separate", "non_us_listing"
        return "import", "stock_or_etf_real_unleveraged"
    if "crypto" in k:
        return "separate", "crypto_pending_decision"
    return "separate", f"type_{k.replace(' ', '_')}"


def to_porty(pos, meta):
    return {
        "ticker": (meta or {}).get("symbolFull"),
        "quantity": pos.get("units"),
        "purchasePrice": pos.get("openRate"),
        "purchaseDate": pos.get("openDateTime"),
        "source": "etoro",
        "externalId": anon("pos", pos.get("positionID") or pos.get("positionId")),
    }


def norm_position(p):
    """La spec usa instrumentID/positionID, pero algunos ejemplos traen camelCase."""
    g = lambda *ks: next((p[k] for k in ks if k in p), None)
    return {
        "positionID": g("positionID", "positionId"),
        "instrumentID": g("instrumentID", "instrumentId"),
        "mirrorID": g("mirrorID", "mirrorId") or 0,
        "settlementTypeID": g("settlementTypeID", "settlementTypeId"),
        "isBuy": g("isBuy"), "leverage": g("leverage"), "units": g("units"),
        "openRate": g("openRate"), "openDateTime": g("openDateTime"),
        "amount": g("amount"), "openConversionRate": g("openConversionRate"),
    }


# ---------------------------------------------------------------- main


def run(api, out, env="demo"):
    report = {"generatedAt": dt.datetime.now(dt.timezone.utc).isoformat(), "env": env}
    E = "demo/" if env == "demo" else "real/"
    AGG = "/api/v1/trading/info/demo/aggregate-portfolio" if env == "demo" else "/api/v1/trading/info/aggregate-portfolio"
    HIST = "/api/v1/trading/info/trade/demo/history" if env == "demo" else "/api/v1/trading/info/trade/history"

    st, me = api.get("/api/v1/me")
    scopes = (me or {}).get("scopes", []) if st == 200 else []
    report["me"] = {"status": st, "scopes": scopes, "hasDemoCid": bool((me or {}).get("demoCid"))}
    bad = [s for s in scopes if ":write" in s or (env == "demo" and (":real:" in s or "trade.real" in s))]
    if bad:
        report["abort"] = "clave con scopes de escritura o de cuenta real: " + ", ".join(bad)
        json.dump(report, out, indent=2, ensure_ascii=False)
        return 2

    # Con claves de usuario, /me puede dar 403 aunque el portfolio funcione. La
    # verificación de entorno es entonces el propio endpoint demo: si no
    # responde, la clave no es Demo y se corta SIN tocar ningún endpoint real.
    st, pnl = api.get(f"/api/v1/trading/info/{E}pnl")
    if st != 200:
        report["abort"] = f"{E}pnl respondió {st}: la clave no es de ese entorno (o no tiene Read)."
        json.dump(report, out, indent=2, ensure_ascii=False)
        return 2
    cp = (pnl or {}).get("clientPortfolio", {}) if st == 200 else {}
    positions = [norm_position(p) for p in cp.get("positions", [])]
    # Las posiciones de mirrors ya están en positions[] con mirrorID>0; las de
    # mirrors[].positions[] se usan solo para enriquecer ids.
    mirror_positions = [norm_position(p) for m in cp.get("mirrors", []) for p in m.get("positions", [])]

    st_agg, agg = api.get(AGG)

    ids = sorted({p["instrumentID"] for p in positions + mirror_positions if p["instrumentID"]})
    if st_agg == 200:
        ids = sorted(set(ids) | {a["instrumentId"] for a in agg.get("instrumentAggregates", [])})
    meta = {}
    for i in range(0, len(ids), 50):
        s, m = api.get("/api/v1/market-data/instruments", {"instrumentIds": ids[i:i + 50]})
        for it in (m or {}).get("instrumentDisplayDatas", []) if s == 200 else []:
            meta[it["instrumentID"]] = it
    s, x = api.get("/api/v1/market-data/exchanges")
    exchanges = {e["exchangeID"]: e["exchangeDescription"] for e in (x or {}).get("exchangeInfo", [])} if s == 200 else {}
    s, t = api.get("/api/v1/market-data/instrument-types")
    types = {x["instrumentTypeID"]: x["instrumentTypeDescription"]
             for x in (t or {}).get("instrumentTypes", [])} if s == 200 else {}

    mapped = {"import": [], "separate": [], "skip": []}
    for p in positions:
        m = meta.get(p["instrumentID"])
        dest, why = classify(p, m, types)
        row = {"reason": why, "instrument": (m or {}).get("symbolFull") or f"id:{p['instrumentID']}",
               "type": types.get((m or {}).get("instrumentTypeID")),
               "exchange": exchanges.get((m or {}).get("exchangeID")),
               "settlement": SETTLEMENT.get(p["settlementTypeID"]), "leverage": p["leverage"],
               "isBuy": p["isBuy"], "units": p["units"], "openRate": p["openRate"],
               "usdPerUnitAtOpen": round(p["amount"] / p["units"], 6) if p["amount"] and p["units"] else None}
        if dest == "import":
            row["porty"] = to_porty(p, m)
        mapped[dest].append(row)

    # Historial: ventana < 1 año (doc oficial), paginado. Luego una sonda con
    # 2 años para ver cómo responde la API a una ventana mayor.
    hist, st_h, page = [], None, 1
    min1 = (dt.date.today() - dt.timedelta(days=364)).isoformat()
    while page <= 10:
        st_h, chunk = api.get(HIST, {"minDate": min1, "page": page, "pageSize": 100})
        if st_h != 200 or not isinstance(chunk, list):
            hist_err = chunk
            break
        hist += chunk
        if len(chunk) < 100:
            break
        page += 1
    st_2y, h2 = api.get(HIST, {"minDate": (dt.date.today() - dt.timedelta(days=729)).isoformat(), "page": 1, "pageSize": 100})
    report["historyWindowProbe"] = {"status1y": st_h, "count1y": len(hist), "status2y": st_2y,
                                    "count2yFirstPage": len(h2) if isinstance(h2, list) else None,
                                    "error2y": h2 if st_2y != 200 else None}
    # Metadata de instrumentos que solo aparecen en el historial (y en la sonda de 2 años).
    extra = sorted({h.get("instrumentId") for h in hist + (h2 if isinstance(h2, list) else [])} - set(meta))
    for i in range(0, len(extra), 50):
        s, m = api.get("/api/v1/market-data/instruments", {"instrumentIds": extra[i:i + 50]})
        for it in (m or {}).get("instrumentDisplayDatas", []) if s == 200 else []:
            meta[it["instrumentID"]] = it
    if isinstance(h2, list):
        report["historyWindowProbe"]["oldestClose2y"] = min((x.get("closeTimestamp") or "")[:10] for x in h2) if h2 else None
        report["historyWindowProbe"]["closesOlderThan1y"] = sum(1 for x in h2 if (x.get("closeTimestamp") or "")[:10] < min1)
    closed = []
    if hist:
        for h in hist:
            m = meta.get(h.get("instrumentId"))
            closed.append({"instrument": (m or {}).get("symbolFull") or f"id:{h.get('instrumentId')}",
                           "type": types.get((m or {}).get("instrumentTypeID")),
                           "exchange": exchanges.get((m or {}).get("exchangeID")),
                           "isBuy": h.get("isBuy"), "leverage": h.get("leverage"),
                           "copied": bool(h.get("parentPositionId")), "units": h.get("units"),
                           "openRate": h.get("openRate"), "closeRate": h.get("closeRate"),
                           "closeTimestamp": h.get("closeTimestamp"), "netProfit": h.get("netProfit"),
                           "fees": h.get("fees")})

    report.update({
        "accountCurrency": (agg or {}).get("accountCurrency") if st_agg == 200 else None,
        "counts": {"positions": len(positions), "mirrors": len(cp.get("mirrors", [])),
                   "instrumentsResolved": f"{len(meta)}/{len(ids)}",
                   **{k: len(v) for k, v in mapped.items()}},
        "positions": mapped,
        "aggregateSample": [
            {k: a.get(k) for k in ("assetCurrency", "netUnits", "avgOpenRate", "avgLeverage")}
            | {"instrument": (meta.get(a["instrumentId"]) or {}).get("symbolFull")}
            for a in (agg or {}).get("instrumentAggregates", [])[:10]] if st_agg == 200 else None,
        "closedHistory": {"status": st_h, "count": len(closed), "sample": closed[:10],
                          "error": None if st_h == 200 else "ver calls"},
        "calls": [{"path": c[0], "status": c[1], "ms": c[2], "rateLimitRemaining": c[3]} for c in api.calls],
    })
    json.dump(report, out, indent=2, ensure_ascii=False, default=str)
    return 0


def main():
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--live", action="store_true")
    g.add_argument("--fixtures")
    ap.add_argument("--env", choices=["demo", "real"], default="demo")
    a = ap.parse_args()
    if a.live:
        k, u = os.environ.get("ETORO_API_KEY"), os.environ.get("ETORO_USER_KEY")
        if not k or not u:
            sys.exit("Faltan ETORO_API_KEY / ETORO_USER_KEY en el entorno")
        api = Api(k, u)
    else:
        api = Fixtures(a.fixtures)
    sys.exit(run(api, sys.stdout, a.env))


if __name__ == "__main__":
    main()
