# 09 — Hybrid Recommender for Bonds

## Why Combine Algorithms?

Each algorithm covers a different part of the problem:

| Algorithm | Strongest when | Weakest when |
|-----------|---------------|-------------|
| Popularity | No client history | Client has strong idiosyncratic preferences |
| CF | Many clients trading same bonds | Sparse overlap between clients |
| Content-Based | Client mandate is narrow and stable | Client trades across many sectors |
| Matrix Factorization | Rich trade history | New clients or new bonds |
| BPR | Active RFQ flow | Silent clients who trade rarely |

No single algorithm wins everywhere. The hybrid approach uses **Feature-Weighted Linear Stacking (FWLS)** — the same method as MovieGEEK — to learn optimal weights for combining these signals, with weights that vary based on the context (how much history we have, what type of client it is, etc.).

---

## The FWLS Architecture

```
For each (client, bond) pair in inventory:

    ┌──────────────────────────────────────┐
    │  Base algorithm scores               │
    │  s_pop   = popularity_score(bond)    │
    │  s_cf    = cf_score(client, bond)    │
    │  s_cb    = content_score(client, bond│
    │  s_mf    = mf_score(client, bond)    │
    │  s_bpr   = bpr_score(client, bond)   │
    └──────────────────────┬───────────────┘
                           │
    ┌──────────────────────▼───────────────┐
    │  Feature functions (context)         │
    │  f1(c) = 1.0 (always on)            │
    │  f2(c) = 1 if trade_count > 5       │
    │  f3(c) = 1 if rfq_count > 10        │
    │  f4(c) = 1 if client_type == "HF"   │
    │  f5(b) = axe_urgency / 5.0          │
    └──────────────────────┬───────────────┘
                           │
    ┌──────────────────────▼───────────────┐
    │  Linear combination (learned weights)│
    │  score = Σ w_ij × s_i × f_j         │
    └──────────────────────────────────────┘
```

---

## Feature Functions for Bonds

Feature functions encode context about the client-bond pair. They modulate how much each algorithm's score should be trusted:

```python
def f1(client_id, isin):
    return 1.0   # constant baseline — always on

def f2(client_id, isin):
    """Active trader — CF and MF are more reliable."""
    trade_count = Trade.objects.filter(
        client_id=client_id,
        trade_timestamp__gte=cutoff(7)
    ).count()
    return 1.0 if trade_count >= 5 else 0.0

def f3(client_id, isin):
    """RFQ-active — BPR signal is more reliable."""
    rfq_count = RFQLog.objects.filter(
        client_id=client_id,
        rfq_timestamp__gte=cutoff(7),
        outcome__in=['done', 'passed']
    ).count()
    return 1.0 if rfq_count >= 10 else 0.0

def f4(client_id, isin):
    """Hedge fund — prefers high-spread, tactical trades."""
    client = Client.objects.get(client_id=client_id)
    return 1.0 if client.client_type == 'HedgeFund' else 0.0

def f5(client_id, isin):
    """Dealer urgency — we really want to move this bond."""
    axe = InventoryAxe.objects.filter(isin=isin, is_active=True).first()
    return (axe.urgency / 5.0) if axe else 0.0

def f6(client_id, isin):
    """Bond is in client's known preferred sector."""
    preferred_sectors = get_preferred_sectors(client_id)
    bond = Bond.objects.get(isin=isin)
    return 1.0 if bond.sector in preferred_sectors else 0.0
```

The key insight: `f2` activates CF and MF weights only when there's enough trading history to make them reliable. For a new client where `f2=0`, those weights drop to zero and the model falls back to `f1` (constant) multiplied by content-based and popularity scores.

---

## Training the FWLS Model

### Step 1 — Generate Training Pairs

For each (client, bond, actual_signal) in historical data:

```python
training_rows = []
for client_id, isin, actual_signal in holdout_set:
    s_pop  = popularity_score(isin)
    s_cf   = cf_score(client_id, isin)
    s_cb   = content_score(client_id, isin)
    s_mf   = mf_score(client_id, isin)
    s_bpr  = bpr_score(client_id, isin)

    feature_row = [
        s_pop  * f1(client_id, isin),
        s_cf   * f1(client_id, isin),
        s_cf   * f2(client_id, isin),
        s_cb   * f1(client_id, isin),
        s_cb   * f6(client_id, isin),
        s_mf   * f1(client_id, isin),
        s_mf   * f2(client_id, isin),
        s_bpr  * f1(client_id, isin),
        s_bpr  * f3(client_id, isin),
        s_pop  * f4(client_id, isin),   # popularity matters more for HFs
        s_mf   * f5(client_id, isin),   # MF score × axe urgency
    ]
    training_rows.append((feature_row, actual_signal))
```

### Step 2 — Fit Linear Regression

```python
from sklearn.linear_model import Ridge   # Ridge instead of plain LR for regularization

X = np.array([row for row, _ in training_rows])
y = np.array([signal for _, signal in training_rows])

model = Ridge(alpha=0.5, fit_intercept=False)
model.fit(X, y)

weights = model.coef_
# Example output:
# [pop×f1: 0.15, cf×f1: 0.08, cf×f2: 0.31, cb×f1: 0.22, cb×f6: 0.18,
#  mf×f1: 0.05, mf×f2: 0.29, bpr×f1: 0.12, bpr×f3: 0.28, ...]
```

**Ridge vs. plain linear regression:** Ridge adds L2 regularization, preventing any single algorithm from being over-weighted due to multicollinearity between the scores.

### Step 3 — Interpret the Weights

The learned weights tell you which algorithms matter:
- High weight on `cf×f2` → CF is very useful for clients with good trade history
- High weight on `bpr×f3` → BPR is best for clients with lots of RFQ activity
- High weight on `cb×f1` → content-based always adds value regardless of history
- Low weight on `mf×f1` → MF alone doesn't add much without sufficient data

---

## Recommendation Pipeline

```python
def recommend_hybrid(client_id, num=6):
    active_inventory = get_active_inventory_isins()
    eligible = mandate_filter(client_id, active_inventory)
    eligible -= get_concentrated_positions(client_id)

    scores = {}
    for isin in eligible:
        # Collect base scores
        base_scores = [
            popularity_score(isin),
            cf_score(client_id, isin),
            cf_score(client_id, isin),
            content_score(client_id, isin),
            content_score(client_id, isin),
            mf_score(client_id, isin),
            mf_score(client_id, isin),
            bpr_score(client_id, isin),
            bpr_score(client_id, isin),
            popularity_score(isin),
            mf_score(client_id, isin),
        ]

        # Apply feature functions
        feature_vec = [
            base_scores[0]  * f1(client_id, isin),
            base_scores[1]  * f1(client_id, isin),
            base_scores[2]  * f2(client_id, isin),
            base_scores[3]  * f1(client_id, isin),
            base_scores[4]  * f6(client_id, isin),
            base_scores[5]  * f1(client_id, isin),
            base_scores[6]  * f2(client_id, isin),
            base_scores[7]  * f1(client_id, isin),
            base_scores[8]  * f3(client_id, isin),
            base_scores[9]  * f4(client_id, isin),
            base_scores[10] * f5(client_id, isin),
        ]

        scores[isin] = np.dot(weights, feature_vec)

    # Boost by inventory urgency before final ranking
    for isin in scores:
        axe = get_axe(isin)
        if axe:
            scores[isin] *= (1 + 0.1 * axe.urgency)   # up to +50% boost for urgency=5

    return sorted(scores, key=scores.get, reverse=True)[:num]
```

---

## Urgency Blending

The dealer's inventory urgency (`f5`) adds a business constraint into the ranking. The model learns to balance client fit against commercial need. But be careful: don't let urgency override client fit so aggressively that you recommend unsuitable bonds just because you need to move them — that erodes trust.

A practical cap: urgency can boost a bond's rank by at most 1–2 positions in the final list.

---

## Cascading Fallbacks

Not every algorithm will produce a score for every client-bond pair. Build a fallback cascade:

```python
def get_best_score(client_id, isin):
    score = hybrid_score(client_id, isin)
    if score is not None:
        return score

    # Fall back through algorithms
    score = cf_score(client_id, isin)
    if score is not None:
        return score * 0.8   # discount for not using full model

    score = content_score(client_id, isin)
    if score is not None:
        return score * 0.6

    return popularity_score(isin) * 0.4   # always available
```

---

## Strengths and Weaknesses

**Strengths:**
- Best overall accuracy — combines the strengths of all algorithms
- Context-aware — weights adapt to data richness per client
- Graceful degradation — feature functions allow falling back smoothly
- Dealer urgency can be incorporated as a first-class signal

**Weaknesses:**
- Most complex to build and maintain — all base algorithms must be running
- Training requires a held-out signal that was not used to train base algorithms (avoid data leakage)
- Weights may need re-calibration as market regimes change
- Latency — calling five algorithms per bond per client can be slow; mitigate by pre-computing and caching nightly
