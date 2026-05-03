# 10 — Practical Considerations

## Fixed Income Is Not Netflix

The algorithmic foundations transfer cleanly from MovieGEEK to bonds. The operational reality is considerably more complex. This document covers the constraints, risks, and practical issues you will encounter building a production bond recommender.

---

## 1. Mandate and Suitability Compliance

This is non-negotiable. Recommending a bond that violates a client's mandate — wrong rating, excluded sector, currency mismatch, duration too long — is not just a bad recommendation. In many jurisdictions it is a regulatory breach.

### Hard Filter (Always Applied First)

```python
def mandate_filter(client_id, candidate_isins):
    mandate = ClientMandate.objects.get(client_id=client_id)
    eligible = set()

    for isin in candidate_isins:
        bond  = Bond.objects.get(isin=isin)
        chars = BondCharacteristics.objects.get(isin=isin)

        if bond.rating_numeric > mandate.min_rating:
            continue   # below minimum rating
        if bond.sector in mandate.excluded_sectors:
            continue   # sector excluded
        if bond.currency not in mandate.allowed_currencies:
            continue   # wrong currency
        if mandate.max_duration and chars.duration > mandate.max_duration:
            continue   # too long duration
        if mandate.ig_only and bond.rating_numeric > 10:
            continue   # sub-investment grade not allowed

        eligible.add(isin)

    return eligible
```

**Run this filter before any scoring, not after.** Never score a bond you cannot legally recommend.

### Position Concentration Check

Even within mandate, a client cannot keep adding to a position indefinitely. Check against issuer concentration limits:

```python
def issuer_concentration_ok(client_id, isin):
    mandate = ClientMandate.objects.get(client_id=client_id)
    if not mandate.max_issuer_pct:
        return True

    bond = Bond.objects.get(isin=isin)
    issuer_id = bond.issuer_id

    # All bonds from same issuer currently held
    current_issuer_exposure = ClientPosition.objects.filter(
        client_id=client_id,
        bond__issuer_id=issuer_id,
        position_date=today()
    ).aggregate(Sum('market_value'))['market_value__sum'] or 0

    total_portfolio_value = ClientPosition.objects.filter(
        client_id=client_id,
        position_date=today()
    ).aggregate(Sum('market_value'))['market_value__sum'] or 1

    current_pct = current_issuer_exposure / total_portfolio_value * 100

    return current_pct < mandate.max_issuer_pct
```

---

## 2. Inventory Staleness

Dealer inventory axes have a short shelf life. An axe set at 8am may be gone by 10am. A bond you recommend at noon that the desk sold at 11am makes you look foolish and wastes the client's time.

### Solutions

**Option A — Soft expiry check at serve time:**
```python
def get_active_inventory_isins():
    return InventoryAxe.objects.filter(
        is_active=True,
        expiry__gt=datetime.now()
    ).values_list('isin', flat=True)
```

Always re-check at recommendation time, never cache inventory status.

**Option B — Real-time inventory feed:**
Subscribe to a message queue from the inventory management system. Update `InventoryAxe.is_active` in real time as the desk trades out of positions.

**Option C — Pre-compute scores, filter at serve time:**
Compute all client-bond scores nightly (slow step). At recommendation time, apply inventory availability as a last-step filter (fast). This balances latency vs. freshness.

---

## 3. Direction Consistency

A recommendation must match the inventory side:

- You have a bond to **sell** (offer) → recommend it to clients likely to **buy**
- You want to **source** a bond (bid) → identify clients likely to **sell**

Every recommendation output must include direction explicitly. A system that doesn't track direction will sometimes recommend a bond to a client who would only sell it — that's wasted outreach.

```python
def recommend_for_offer(client_id, isin, model):
    """We are offering (selling) this bond. Score client's buy appetite."""
    return model.predict_buy_score(client_id, isin)

def recommend_for_bid(client_id, isin, model):
    """We are bidding (buying) this bond. Score client's sell appetite."""
    return model.predict_sell_score(client_id, isin)
```

---

## 4. Market Regime Awareness

Fixed income preferences shift dramatically with rates and credit cycles. During a risk-off event:
- Clients who were buying BB-rated names may suddenly want to reduce risk
- Duration appetite collapses — long-end bonds become hard to move
- Correlations between bonds increase — everything sells together

A static model trained on data from a low-volatility period will give poor recommendations during spread-widening events.

### Mitigations

1. **Short training window** — use 30-day rolling window rather than 1-year history. Recent behavior is a better guide to current appetite.
2. **Spread-adjusted features** — include current OAS vs. historical OAS as a feature. "Is this bond cheap or rich relative to its recent history?"
3. **Market regime feature** — add a feature that flags current regime (risk-on/risk-off) based on index spreads or VIX equivalent. The hybrid model can learn different weights per regime.
4. **Manual override** — give traders and salespeople the ability to boost or suppress specific bonds or sectors in recommendations during unusual market conditions.

---

## 5. Explainability

Sales teams need to understand why a bond is being recommended. "The model says so" is not acceptable when calling a client.

### Minimum Viable Explanation

For each recommendation, generate a human-readable reason:

```python
def generate_explanation(client_id, isin, scores_by_algorithm):
    reasons = []

    if scores_by_algorithm['content_based'] > 0.7:
        bond = Bond.objects.get(isin=isin)
        chars = BondCharacteristics.objects.get(isin=isin)
        reasons.append(
            f"Matches your recent activity in {bond.sector} "
            f"{round(chars.duration)}yr bonds"
        )

    if scores_by_algorithm['collaborative_filtering'] > 0.6:
        reasons.append(
            "Clients with similar portfolios have been active in this name"
        )

    if scores_by_algorithm['popularity'] > 0.8:
        reasons.append(
            f"Top traded bond in {bond.sector} this week by volume"
        )

    axe = InventoryAxe.objects.filter(isin=isin, is_active=True).first()
    if axe and axe.urgency >= 4:
        reasons.append(f"Available at {axe.axe_spread:.0f}bps (offer)")

    return "; ".join(reasons) if reasons else "Good fit based on portfolio analysis"
```

The best recommendations combine a data-driven reason with a market context the salesperson can expand on.

---

## 6. Feedback Loop and Model Improvement

Recommendations should improve over time by tracking outcomes:

| Outcome | Signal to record |
|---------|-----------------|
| Client trades after recommendation | Strong positive — recommendation worked |
| Client passes on recommendation | Negative — mismatched, log the reason if possible |
| Client RFQs but doesn't trade (away) | Moderate — interest but price or size was wrong |
| Recommendation never sent to client | Neutral — don't assume anything |

```python
class RecommendationOutcome(models.Model):
    client_id    = models.CharField(max_length=50)
    isin         = models.CharField(max_length=12)
    recommended_at = models.DateTimeField()
    algorithm    = models.CharField(max_length=50)
    rank_position = models.IntegerField()          # was it rec #1 or rec #5?
    outcome      = models.CharField(max_length=20) # "traded", "passed", "no_contact"
    notional_traded = models.BigIntegerField(null=True)
    outcome_at   = models.DateTimeField(null=True)
```

Use this table to:
- Compute hit rate per algorithm (% of recommendations that resulted in trades)
- Compare algorithms A/B style by routing different clients to different models
- Retrain the FWLS weights using outcome data rather than historical signals

---

## 7. Offline Evaluation Metrics for Bonds

Standard metrics from `10_evaluation.md` apply, with bond-specific adaptations:

| Metric | Definition | Bond adaptation |
|--------|-----------|----------------|
| Hit Rate@K | Did the client trade any of the top-K recommended bonds? | K=5 is typical for a daily run |
| Recall@K | Of bonds the client traded, what fraction appeared in top-K? | Weight by notional (large trades matter more) |
| Notional-Weighted Precision | Precision weighted by the notional traded on hits | Captures commercial impact, not just accuracy |
| Axe Coverage | % of inventory axes recommended to at least one client | Ensures all inventory gets surfaced |

```python
def notional_weighted_precision(recommended_isins, trades_dict, k=5):
    """
    recommended_isins: ordered list of recommended ISINs
    trades_dict: {isin: notional_traded} for this client in evaluation period
    """
    hits_notional = sum(
        trades_dict[isin]
        for isin in recommended_isins[:k]
        if isin in trades_dict
    )
    total_notional = sum(trades_dict.values())
    return hits_notional / total_notional if total_notional > 0 else 0.0
```

---

## 8. Operational Architecture

For a production deployment:

```
Nightly batch (2am–6am):
  ├── Ingest trade history from OMS
  ├── Ingest positions from custodian feeds
  ├── Update bond reference data from Bloomberg
  ├── Retrain MF and BPR models (rolling 60-day window)
  ├── Recompute bond similarities (content + co-trading)
  ├── Recompute client profiles
  ├── Pre-compute all client × inventory scores
  └── Cache ranked recommendations per client

Morning (7am, before market open):
  ├── Ingest fresh inventory axes from traders
  ├── Apply mandate filter to pre-computed scores
  └── Publish morning run recommendations to sales UI

Intraday (streaming):
  ├── Update inventory availability as axes expire or are traded
  ├── Log new RFQs and trades as they occur
  └── Re-rank on demand if client requests a fresh recommendation
```

---

## Summary

Building a bond recommender on the MovieGEEK framework is conceptually straightforward. The algorithms translate directly. The hard work is in:

1. **Data plumbing** — connecting to OMS, custodians, Bloomberg, and trading platforms
2. **Mandate compliance** — hard filters that cannot be bypassed by any model score
3. **Inventory freshness** — recommendations must only surface what you actually have
4. **Direction awareness** — buy and sell are fundamentally different recommendations
5. **Explainability** — sales teams need reasons, not scores
6. **Regime sensitivity** — models trained in calm markets fail during dislocations
7. **Feedback loops** — systematic tracking of recommendation outcomes drives improvement

The recommender is a tool that makes salespeople more effective — not a replacement for their judgment. The best implementations give salespeople a prioritized call list with context, and let them apply their own expertise on top.
