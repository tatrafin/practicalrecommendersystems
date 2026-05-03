# 03 — Data Models

Below is the schema adapted from MovieGEEK for the IG bond recommender. Each table maps to a concept from the movie system, with fixed income specifics layered on top.

---

## Schema Overview

```
Bond ──< BondCharacteristics (1:1)
Bond ──< MarketData (1:many, time-series)
Bond ──< InventoryAxe (1:many)

Client ──< ClientMandate (1:1)
Client ──< ClientPosition (1:many)

Client ──< Trade >── Bond          (explicit signal)
Client ──< RFQLog >── Bond         (implicit signal)

Bond ──< BondSimilarity >── Bond   (content-based, pre-computed)
Client ──< ClientSimilarity >── Client  (CF, pre-computed)
```

---

## Core Entities

### Bond

The central entity — equivalent to `Movie`.

```python
class Bond(models.Model):
    isin            = models.CharField(max_length=12, primary_key=True)
    cusip           = models.CharField(max_length=9, null=True)
    issuer_name     = models.CharField(max_length=255)
    issuer_id       = models.CharField(max_length=50)   # groups bonds by issuer
    sector          = models.CharField(max_length=100)  # e.g. "Financials"
    sub_sector      = models.CharField(max_length=100, null=True)
    country         = models.CharField(max_length=3)    # ISO country code
    currency        = models.CharField(max_length=3)    # "USD", "EUR"
    maturity_date   = models.DateField()
    coupon          = models.DecimalField(max_digits=6, decimal_places=3)
    coupon_type     = models.CharField(max_length=20)   # "Fixed", "Float"
    issue_size      = models.BigIntegerField()          # face value in currency units
    seniority       = models.CharField(max_length=50)   # "Sr Unsecured", "Sub"
    rating_sp       = models.CharField(max_length=5)    # "AA+", "A-", "BBB"
    rating_moodys   = models.CharField(max_length=5)
    rating_numeric  = models.IntegerField()             # 1=AAA ... 10=BBB-
```

`rating_numeric` is a derived field mapping letter ratings to integers — makes range queries easier (e.g., "find bonds rated A- or better").

### BondCharacteristics (computed features)

Derived analytical attributes used by content-based matching. Updated daily.

```python
class BondCharacteristics(models.Model):
    isin            = models.OneToOneField(Bond, primary_key=True)
    duration        = models.DecimalField(max_digits=6, decimal_places=3)   # years
    dv01_per_1m     = models.DecimalField(max_digits=10, decimal_places=2)  # $ per $1M
    oas_bps         = models.DecimalField(max_digits=7, decimal_places=2)   # current OAS
    z_spread        = models.DecimalField(max_digits=7, decimal_places=2)
    ytm             = models.DecimalField(max_digits=6, decimal_places=4)   # yield
    price           = models.DecimalField(max_digits=8, decimal_places=4)   # clean price
    price_date      = models.DateField()
    liquidity_score = models.DecimalField(max_digits=4, decimal_places=2)   # 0–1
```

`liquidity_score` captures how easy the bond is to trade — derived from average daily volume, bid-ask spread, and issue size. Illiquid bonds should be weighted lower in recommendations unless the client specifically trades illiquid paper.

---

### Client

Equivalent to `User`. Represents a fund, portfolio, or trading desk.

```python
class Client(models.Model):
    client_id       = models.CharField(max_length=50, primary_key=True)
    client_name     = models.CharField(max_length=255)
    client_type     = models.CharField(max_length=50)   # "AssetManager", "InsuranceCo", "PensionFund", "HedgeFund"
    salesperson_id  = models.CharField(max_length=50)   # covering salesperson
    coverage_region = models.CharField(max_length=10)   # "EMEA", "AMER", "APAC"
    onboarded_date  = models.DateField()
```

### ClientMandate

Hard constraints — acts as a filter layer before any recommendation is shown.

```python
class ClientMandate(models.Model):
    client          = models.OneToOneField(Client, primary_key=True)
    min_rating      = models.IntegerField()              # numeric rating floor
    excluded_sectors = models.JSONField(default=list)   # ["Tobacco", "Weapons"]
    max_duration    = models.DecimalField(max_digits=5, decimal_places=2, null=True)
    max_issuer_pct  = models.DecimalField(max_digits=5, decimal_places=2, null=True)
    allowed_currencies = models.JSONField(default=list) # ["USD", "EUR"]
    ig_only         = models.BooleanField(default=True)
    mandate_notes   = models.TextField(null=True)
```

---

## Signal Tables

### Trade

Explicit feedback — equivalent to `Rating`. The strongest signal.

```python
class Trade(models.Model):
    trade_id        = models.CharField(max_length=50, primary_key=True)
    client          = models.ForeignKey(Client, on_delete=models.CASCADE)
    isin            = models.CharField(max_length=12)
    direction       = models.CharField(max_length=4)    # "BUY" or "SELL"
    notional        = models.BigIntegerField()           # face value
    price           = models.DecimalField(max_digits=8, decimal_places=4)
    oas_at_trade    = models.DecimalField(max_digits=7, decimal_places=2, null=True)
    trade_timestamp = models.DateTimeField()
    venue           = models.CharField(max_length=50)   # "MKTAXS", "TRADEWEB", "VOICE"
    trader_id       = models.CharField(max_length=50)
```

**Rating equivalent:** In the movie system, a rating is a single number. Here, the "rating" is richer:
- **Direction** (BUY vs SELL) — critical context
- **Notional** — size signals conviction; a $50M trade is a stronger endorsement than $1M
- **OAS at trade** — at what spread did they trade? Signals their entry point preference

### RFQLog

Implicit feedback — equivalent to `Log`. Client showed interest but may not have traded.

```python
class RFQLog(models.Model):
    client          = models.ForeignKey(Client, on_delete=models.CASCADE)
    isin            = models.CharField(max_length=12)
    direction       = models.CharField(max_length=4)
    rfq_notional    = models.BigIntegerField()
    rfq_timestamp   = models.DateTimeField()
    outcome         = models.CharField(max_length=10)  # "done", "passed", "away", "no_cover"
    platform        = models.CharField(max_length=50)
```

Outcomes ranked by signal strength:
- `"done"` — traded (also in `Trade` table; strongest signal)
- `"passed"` — client looked but didn't trade (strong interest)
- `"away"` — client traded but with another dealer (moderate interest)
- `"no_cover"` — we couldn't cover (neutral; client may still want it)

### ClientPosition

Current holdings — used to detect concentration and avoid recommending what they already hold in size.

```python
class ClientPosition(models.Model):
    client          = models.ForeignKey(Client, on_delete=models.CASCADE)
    isin            = models.CharField(max_length=12)
    notional_held   = models.BigIntegerField()
    market_value    = models.BigIntegerField()
    pnl_mtm         = models.IntegerField()             # unrealized P&L
    position_date   = models.DateField()

    class Meta:
        unique_together = ('client', 'isin', 'position_date')
```

---

## Inventory Table

What you have to sell (or want to buy). This gates all recommendations.

```python
class InventoryAxe(models.Model):
    isin            = models.CharField(max_length=12)
    side            = models.CharField(max_length=5)    # "OFFER" (we sell) or "BID" (we buy)
    size_available  = models.BigIntegerField()          # face value we can do
    axe_price       = models.DecimalField(max_digits=8, decimal_places=4)
    axe_spread      = models.DecimalField(max_digits=7, decimal_places=2)  # OAS bps
    urgency         = models.IntegerField()             # 1 (low) to 5 (urgent)
    trader_id       = models.CharField(max_length=50)
    axe_timestamp   = models.DateTimeField()
    expiry          = models.DateTimeField()
    is_active       = models.BooleanField(default=True)
```

---

## Pre-Computed Similarity Tables

Built offline by the builder modules, queried online by the recommender.

### BondSimilarity (content-based)

```python
class BondSimilarity(models.Model):
    source_isin     = models.CharField(max_length=12)
    target_isin     = models.CharField(max_length=12)
    similarity      = models.DecimalField(max_digits=10, decimal_places=6)
    similarity_type = models.CharField(max_length=20)   # "characteristics", "sector_duration"
    computed_date   = models.DateField()

    class Meta:
        unique_together = ('source_isin', 'target_isin', 'similarity_type')
```

### ClientSimilarity (collaborative filtering)

```python
class ClientSimilarity(models.Model):
    source_client   = models.CharField(max_length=50)
    target_client   = models.CharField(max_length=50)
    similarity      = models.DecimalField(max_digits=10, decimal_places=6)
    computed_date   = models.DateField()
```

---

## How Algorithms Use the Schema

| Algorithm | Primary read tables | Output |
|-----------|-------------------|--------|
| Popularity | `Trade`, `RFQLog` | Ranked `InventoryAxe` list |
| Neighborhood CF | `Trade`, `ClientSimilarity` | Ranked `InventoryAxe` list |
| Content-Based | `Trade`, `BondSimilarity`, `BondCharacteristics` | Ranked `InventoryAxe` list |
| Matrix Factorization | `Trade` (batch) | Factor files on disk |
| BPR | `RFQLog`, `Trade` (batch) | Factor files on disk |
| FWLS | All of the above | Weighted scores per client-bond pair |
| Mandate filter | `ClientMandate`, `BondCharacteristics` | Hard pass/fail |

---

## Key Design Decisions

1. **ISIN as primary key for bonds** — ISINs are globally unique and stable. CUSIPs are also stored for US market compatibility.
2. **Notional, not quantity** — bonds trade in face value notional, not number of units. All size fields are in currency units.
3. **Direction is explicit** — every trade has a BUY or SELL label. This means recommendations are directional too.
4. **Inventory checked at serve time** — `InventoryAxe.is_active` and `expiry` are re-checked when generating final recommendations, because inventory can move between model build and recommendation delivery.
5. **Positions are date-stamped** — positions change daily. Always use `position_date = today` for current state.
