# 08 — BPR: Ranking from Implicit Signals

## The Core Idea

Bayesian Personalized Ranking (BPR) is designed for situations where you have implicit feedback — signals of interest without explicit ratings. In fixed income, this maps directly to **RFQ activity, bond lookups, and trade inquiries** as opposed to completed trades.

A client who sent an RFQ for a bond but didn't trade (perhaps you were away on price) is expressing interest. A client who repeatedly inquires about a sector is building appetite. BPR learns to rank bonds higher when clients show these signals, even without a confirmed transaction.

---

## Implicit Signals in Fixed Income

| Signal | Strength | Source |
|--------|----------|--------|
| Completed trade (BUY) | Very strong | Trade table |
| Completed trade (SELL) | Strong (sell interest) | Trade table |
| RFQ: `done` | Very strong | RFQLog |
| RFQ: `passed` (client looked, didn't trade) | Strong | RFQLog |
| RFQ: `away` (traded elsewhere) | Moderate | RFQLog |
| RFQ: `no_cover` | Weak | RFQLog |
| Bond detail viewed (if web-based) | Weak | Clickstream |

Unlike explicit ratings, you only observe **positive** interactions. A bond a client hasn't inquired about isn't necessarily unappealing — they may simply not have encountered it.

---

## Constructing the Training Data

BPR trains on **triples:** (client, positive_bond, negative_bond).

```python
def sample_training_triples(client_id, num_samples=50):
    # Positive set: bonds client has traded or inquired about
    positive_bonds = set(
        list(Trade.objects.filter(client_id=client_id, direction='BUY')
                          .values_list('isin', flat=True)) +
        list(RFQLog.objects.filter(client_id=client_id,
                                   outcome__in=['done', 'passed'])
                           .values_list('isin', flat=True))
    )

    if not positive_bonds:
        return []

    # Negative set: bonds in the universe the client has NOT interacted with
    all_bonds     = set(Bond.objects.values_list('isin', flat=True))
    negative_pool = all_bonds - positive_bonds

    triples = []
    for _ in range(num_samples):
        pos = random.choice(list(positive_bonds))
        neg = random.choice(list(negative_pool))
        triples.append((client_id, pos, neg))

    return triples
```

**Weighting positive samples:** Not all positives are equal. A $50M trade is stronger than a "passed" RFQ. Sample positive bonds proportionally to signal strength:

```python
def weighted_positive_sample(client_id):
    candidates = []
    weights    = []
    for trade in Trade.objects.filter(client_id=client_id, direction='BUY'):
        candidates.append(trade.isin)
        weights.append(log1p(trade.notional / 1_000_000) * 3.0)   # trades weighted high
    for rfq in RFQLog.objects.filter(client_id=client_id, outcome='passed'):
        candidates.append(rfq.isin)
        weights.append(1.0)   # RFQ pass weighted lower
    return random.choices(candidates, weights=weights, k=1)[0]
```

---

## Model Structure

Same latent factor structure as matrix factorization:

- `P[client]` — client preference vector (k dimensions)
- `Q[bond]` — bond profile vector (k dimensions)
- Score: `s(client, bond) = P[client] · Q[bond]`

No bias terms — BPR cares about relative ranking, not absolute score.

---

## Training

```python
class BondBPR:
    def __init__(self, k=8, lr=0.05, reg=0.005, epochs=15):
        self.k   = k
        self.lr  = lr
        self.reg = reg

    def train(self, client_ids, days=14):
        self.P = {c: np.random.normal(0, 0.01, self.k) for c in client_ids}
        self.Q = {i: np.random.normal(0, 0.01, self.k) for i in all_bonds}

        for epoch in range(self.epochs):
            for client_id in client_ids:
                triples = sample_training_triples(client_id, num_samples=100)
                for client, pos_bond, neg_bond in triples:
                    self._update(client, pos_bond, neg_bond)

    def _update(self, client, pos_bond, neg_bond):
        p  = self.P[client]
        qi = self.Q[pos_bond]
        qj = self.Q[neg_bond]

        # Score difference: positive bond should outscore negative bond
        x_uij     = np.dot(p, qi) - np.dot(p, qj)
        sigmoid_x = 1.0 / (1.0 + np.exp(x_uij))  # gradient signal

        # Update: push pos_bond score up, neg_bond score down for this client
        self.P[client]    += self.lr * (sigmoid_x * (qi - qj) - self.reg * p)
        self.Q[pos_bond]  += self.lr * (sigmoid_x * p          - self.reg * qi)
        self.Q[neg_bond]  += self.lr * (-sigmoid_x * p         - self.reg * qj)
```

The model is learning: "for this client, the positive bond should rank above the negative bond."

---

## Handling Direction with BPR

BPR can be extended to be direction-aware by training **separate models** for buy-side and sell-side signals:

```python
# BPR-BUY: trained on bonds clients have bought / sent buy RFQs for
bpr_buy = BondBPR(k=8)
bpr_buy.train(client_ids, signal_type='BUY')

# BPR-SELL: trained on bonds clients have sold / sent sell RFQs for
bpr_sell = BondBPR(k=8)
bpr_sell.train(client_ids, signal_type='SELL')
```

At recommendation time:
- **Your offer inventory** → use `bpr_buy` scores (find buyers)
- **Your bid inventory** → use `bpr_sell` scores (find sellers)

---

## Recency Weighting

RFQ signals from this morning are more relevant than ones from 6 days ago. Weight positive samples by recency:

```python
def recency_weight(timestamp, halflife_days=3):
    age_days = (datetime.now() - timestamp).total_seconds() / 86400
    return 2 ** (-age_days / halflife_days)
```

A signal from today has weight 1.0. A signal from 3 days ago has weight 0.5. A signal from 6 days ago has weight 0.25. This ensures the model focuses on current appetite.

---

## Serving Recommendations

```python
def recommend_bpr(client_id, model, num=6):
    if client_id not in model.P:
        return []   # no history for this client — fall back to popularity

    active_inventory = get_active_inventory_isins()
    eligible         = mandate_filter(client_id, active_inventory)
    already_active   = get_recent_positive_bonds(client_id)   # don't repeat what they just traded

    scores = {
        isin: np.dot(model.P[client_id], model.Q[isin])
        for isin in eligible
        if isin not in already_active and isin in model.Q
    }

    return sorted(scores, key=scores.get, reverse=True)[:num]
```

---

## BPR vs. Matrix Factorization for Bonds

| Aspect | Matrix Factorization | BPR |
|--------|---------------------|-----|
| Signal used | Trade signals (weighted) | RFQ + trade (binary positive/negative) |
| Training objective | Minimize prediction error | Maximize ranking accuracy |
| Bias terms | Yes (global mean, per client/bond) | No |
| Best for | Clients with rich explicit trade history | All clients, including those with only RFQ activity |
| Cold start | Fails | Fails (same) |
| Interpretability | Moderate | Low |
| Direction handling | Via signal sign | Via separate buy/sell models |

**Practical rule of thumb:** Use BPR when you want to surface bonds from RFQ activity even when no trade resulted. Use Matrix Factorization when you trust your trade signals to be a clean indication of preference.

---

## Practical Latency Concern

BPR scores are computed by a dot product — extremely fast. At request time, scoring 5,000 bonds for a client takes milliseconds:

```python
scores = {isin: float(np.dot(P_client, Q[isin]))
          for isin in inventory_isins if isin in Q}
```

For desks with large client bases and large bond universes, pre-compute all scores nightly and cache them. At recommendation time, just filter the cached scores to current inventory.

---

## Strengths and Weaknesses

**Strengths:**
- Uses all interest signals, not just completed trades
- Captures "soft" intent — a client who passes on multiple bonds in a sector is telling you something
- Fast inference (simple dot product)
- Optimizes what matters: ranking, not score prediction

**Weaknesses:**
- Cold start — needs at least a few positive signals per client
- Noisy negatives — an un-inquired bond might just be unknown, not unwanted
- No magnitude — a $1M RFQ and a $100M trade look the same if both are "positive"
- Requires careful tuning of the negative sampling strategy
