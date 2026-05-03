# 02 — Data Sources

A bond recommender is only as good as its inputs. Unlike movie ratings, which are explicit and clean, bond trading data is fragmented across multiple systems and requires significant enrichment before it is useful.

---

## Source 1 — Client Trade History (Past 7 Days)

This is the primary signal. What has each client actually traded recently?

**Where it comes from:** Your order management system (OMS) or trade management system (TMS). Internally, this may be a Bloomberg TSOX feed, Tradeweb/MarketAxess execution data, or a proprietary blotter.

**Key fields:**

| Field | Description | Example |
|-------|-------------|---------|
| `client_id` | Unique client/fund identifier | `"PIMCO_TOTAL_RETURN"` |
| `isin` | Bond identifier | `"XS2345678901"` |
| `direction` | Buy or Sell | `"BUY"` |
| `notional` | Face value traded (USD/EUR) | `5_000_000` |
| `price` | Execution price (% of par) | `98.75` |
| `spread` | OAS at execution (bps) | `142` |
| `trade_timestamp` | Date and time of execution | `2024-01-15 10:23:00` |
| `trader_id` | Which desk executed | `"IG_CREDIT_NY"` |

**7-day window rationale:** Fixed income appetite is short-lived. A client who was buying 5yr Tech paper last week is likely still interested. Three months ago is stale — mandates change, portfolio constraints shift, rates move.

---

## Source 2 — Client Current Positions

What does the client hold today? This tells you:
- What sectors/issuers they are already concentrated in (avoid recommending more)
- What their duration profile looks like (are they long or short duration?)
- Where they might want to trim (sell-side recommendations)

**Where it comes from:** Custodian feeds (State Street, BNY Mellon, Euroclear), prime brokerage reports, or client-reported holdings if they share them.

**Key fields:**

| Field | Description | Example |
|-------|-------------|---------|
| `client_id` | Client identifier | `"PIMCO_TOTAL_RETURN"` |
| `isin` | Bond held | `"XS2345678901"` |
| `notional_held` | Current face value held | `10_000_000` |
| `market_value` | Current market value | `9_875_000` |
| `pnl_mtm` | Mark-to-market P&L | `-125_000` |
| `position_date` | Snapshot date | `2024-01-22` |

**Position data quality warning:** Not all clients share positions. Some share weekly, some daily, some not at all. Your system must gracefully handle missing position data — falling back to inferring positions from trade history.

---

## Source 3 — Dealer Inventory (Axes)

What bonds are you actually trying to move? The recommender must only surface bonds you have.

**Where it comes from:** Your internal inventory management system or risk system. Often distributed as a daily "run" (email or Bloomberg message) that the system ingests.

**Key fields:**

| Field | Description | Example |
|-------|-------------|---------|
| `isin` | Bond identifier | `"XS2345678901"` |
| `side` | Offer (we sell) or Bid (we buy) | `"OFFER"` |
| `size_available` | Notional we can trade | `15_000_000` |
| `axe_price` | Our quoted price | `98.50` |
| `axe_spread` | Our quoted OAS (bps) | `145` |
| `urgency` | How keen are we to move it (1–5) | `4` |
| `axe_timestamp` | When this axe was set | `2024-01-22 08:00:00` |
| `expiry` | When the axe expires | `2024-01-22 17:00:00` |

**Urgency** is a dealer-side signal. A bond the desk is very keen to move (urgency=5) should be surfaced to more clients and ranked higher, all else equal.

---

## Source 4 — Bond Reference Data (Static Characteristics)

Structural attributes of each bond. This is the "content" used by the content-based algorithm.

**Where it comes from:** Bloomberg (via BDH/BDP), Refinitiv, or a fixed income data vendor.

**Key fields:**

| Field | Description | Example |
|-------|-------------|---------|
| `isin` | Bond identifier | `"XS2345678901"` |
| `issuer_name` | Name of issuing company | `"Apple Inc"` |
| `issuer_id` | Issuer-level grouping | `"AAPL"` |
| `sector` | GICS or ICE sector | `"Technology"` |
| `sub_sector` | More granular | `"Hardware"` |
| `country` | Issuer country | `"US"` |
| `currency` | Bond currency | `"USD"` |
| `rating_sp` | S&P rating | `"AA+"` |
| `rating_moodys` | Moody's rating | `"Aa1"` |
| `maturity_date` | Final maturity | `2030-09-15` |
| `coupon` | Annual coupon rate | `3.85` |
| `coupon_type` | Fixed or floating | `"Fixed"` |
| `issue_size` | Total issue (face value) | `1_000_000_000` |
| `seniority` | Sr Unsecured, Sub, etc. | `"Sr Unsecured"` |

---

## Source 5 — Market Data (Live/Daily)

Current pricing and risk metrics. A bond's attractiveness changes daily.

**Where it comes from:** Bloomberg live feeds, ICE/Markit evaluated prices, or your own pricing model.

**Key fields:**

| Field | Description | Example |
|-------|-------------|---------|
| `isin` | Bond identifier | |
| `oas_bps` | Option-adjusted spread (bps) | `142` |
| `g_spread` | Spread vs. govt benchmark (bps) | `155` |
| `z_spread` | Zero-volatility spread (bps) | `148` |
| `duration` | Modified duration (years) | `4.8` |
| `dv01` | Dollar value of 1bp move | `4_800` per $1M |
| `ytm` | Yield to maturity | `5.42%` |
| `price` | Clean price (% of par) | `98.75` |
| `price_date` | Pricing date | `2024-01-22` |

---

## Source 6 — Implicit Signals (RFQs and Inquiries)

Even when a trade doesn't happen, a client's request-for-quote (RFQ) tells you something — they were interested.

**Where it comes from:** Electronic trading platforms (MarketAxess, Tradeweb), or internal RFQ logs.

**Key fields:**

| Field | Description | Example |
|-------|-------------|---------|
| `client_id` | Client who sent RFQ | |
| `isin` | Bond requested | |
| `direction` | Buy or Sell | |
| `rfq_size` | Requested size | `2_000_000` |
| `rfq_timestamp` | Time of request | |
| `outcome` | `"done"`, `"passed"`, `"away"` | `"passed"` |

`"passed"` means the client looked but didn't trade — strong interest signal even without a transaction.

---

## Source 7 — Client Mandate / Profile

Hard constraints that must be respected regardless of algorithmic score.

**Where it comes from:** Client onboarding documents, mandate letters, CRM system.

**Key fields:**

| Field | Description | Example |
|-------|-------------|---------|
| `client_id` | Client identifier | |
| `allowed_ratings` | Minimum credit rating | `["AAA","AA","A","BBB"]` |
| `excluded_sectors` | Sectors not permitted | `["Tobacco", "Weapons"]` |
| `max_duration` | Maximum duration limit | `7.0` |
| `max_single_issuer_pct` | Max % in one issuer | `5.0` |
| `currency_restriction` | Allowed currencies | `["USD", "EUR"]` |
| `client_type` | Pension, Insurance, AM, HF | `"InsuranceCo"` |

These constraints act as a **hard filter** — no algorithmic score, however high, should result in a recommendation that violates a mandate.

---

## Data Freshness Requirements

| Source | Required freshness | Update frequency |
|--------|-------------------|-----------------|
| Inventory / axes | Real-time to intraday | Intraday (or streaming) |
| Trade history | End of day | Daily |
| Client positions | End of day | Daily (or T+1) |
| Market data | Intraday | Hourly or live |
| Bond reference data | Weekly or on change | Weekly |
| Client mandates | On change | Event-driven |
| RFQ logs | Real-time | Streaming |

**Key implication:** Inventory axes expire. A recommendation generated from morning inventory must not be served in the afternoon if the bond has been sold. The recommender must check current inventory at serve time, not just at model-build time.
