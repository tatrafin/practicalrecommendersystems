# 07 — Matrix Factorization for Bonds

## The Core Idea

Matrix factorization (Funk SVD) learns **latent preference dimensions** that explain why clients trade the bonds they do. Instead of computing explicit similarity between bonds or clients, it decomposes the client-bond interaction matrix into compact latent representations.

In fixed income, those latent dimensions might correspond to real things:
- Factor 1: duration preference (short vs. long)
- Factor 2: risk appetite (high-quality AAA vs. high-spread BBB)
- Factor 3: sector tilt (Financials vs. Industrials)
- Factor 4: liquidity preference (benchmark bonds vs. off-the-run)

The model discovers these dimensions from data without being told what they are.

---

## Constructing the Interaction Matrix

The matrix has:
- **Rows:** clients
- **Columns:** bond ISINs
- **Values:** interaction signals (constructed from trades, as described in `05_collaborative_filtering.md`)

```python
def build_interaction_matrix(days=30):
    trades = Trade.objects.filter(
        trade_timestamp__gte=cutoff(days)
    ).values('client_id', 'isin', 'notional', 'direction')

    # Build {client_id: {isin: signal}} dict
    matrix = defaultdict(dict)
    for trade in trades:
        signal = compute_signal(trade['notional'], trade['direction'])
        matrix[trade['client_id']][trade['isin']] = signal

    return matrix
```

Then normalize per client (z-score) so that a large fund's $500M trades don't drown out a smaller fund's $5M trades.

---

## Model Structure

Same as MovieGEEK's Funk SVD, with bond-specific adjustments:

```
predicted_score(client, bond) = global_mean
                               + client_bias[client]
                               + bond_bias[bond]
                               + P[client] · Q[bond]
```

Where:
- `P[client]` — k-dimensional vector representing the client's latent preferences
- `Q[bond]` — k-dimensional vector representing the bond's latent profile
- `client_bias` — some clients are systematically more active buyers (positive bias)
- `bond_bias` — some bonds are universally sought after (positive bias)

---

## Training with SGD

```python
class BondMatrixFactorization:
    def __init__(self, k=10, lr=0.005, reg=0.01, epochs=20):
        self.k       = k
        self.lr      = lr    # learning rate (higher than movie — bond data is sparser)
        self.reg     = reg   # regularization
        self.epochs  = epochs

    def train(self, interaction_matrix):
        # Initialize factors randomly (small values)
        self.P = {c: np.random.normal(0, 0.1, self.k) for c in clients}
        self.Q = {i: np.random.normal(0, 0.1, self.k) for i in bonds}
        self.client_bias = {c: 0.0 for c in clients}
        self.bond_bias   = {i: 0.0 for i in bonds}
        self.global_mean = compute_global_mean(interaction_matrix)

        for epoch in range(self.epochs):
            for client_id, isin, signal in all_interactions(interaction_matrix):
                error = signal - self.predict(client_id, isin)

                # Update biases
                self.client_bias[client_id] += self.lr * (error - self.reg * self.client_bias[client_id])
                self.bond_bias[isin]         += self.lr * (error - self.reg * self.bond_bias[isin])

                # Update latent factors
                p = self.P[client_id].copy()
                q = self.Q[isin].copy()
                self.P[client_id] += self.lr * (error * q - self.reg * p)
                self.Q[isin]       += self.lr * (error * p - self.reg * q)

    def predict(self, client_id, isin):
        return (self.global_mean
                + self.client_bias.get(client_id, 0)
                + self.bond_bias.get(isin, 0)
                + np.dot(self.P.get(client_id, np.zeros(self.k)),
                         self.Q.get(isin, np.zeros(self.k))))
```

**Bond-specific tuning differences from movie system:**
- `k=10` latent factors (vs. 20–40 for movies) — bond trading data is much sparser
- `lr=0.005` — slightly higher learning rate to converge faster with sparse data
- `epochs=20` — more passes to compensate for sparsity

---

## Hyperparameter Considerations

| Parameter | Movie system | Bond system | Reason |
|-----------|-------------|-------------|--------|
| k (factors) | 20–40 | 5–15 | Less data → risk of overfitting with many factors |
| Learning rate | 0.002 | 0.003–0.01 | Faster convergence needed on sparse data |
| Regularization | 0.002 | 0.01–0.05 | Higher regularization to prevent overfitting |
| Training window | All history | 30–90 days | Older trades reflect outdated preferences |

### Rolling Retraining

Client preferences in fixed income shift faster than movie tastes. A client who was long duration six months ago may now be actively reducing duration risk. Retrain weekly on a rolling window of recent data.

```python
# Retrain every Monday on the past 60 days
if day_of_week == 'Monday':
    model.train(interaction_matrix(days=60))
    model.save('mf_factors.json')
```

---

## Handling Direction in the Signal

The sign of the interaction signal encodes direction:
- Positive signal → buy interest
- Negative signal → sell interest

During training, the model learns that some clients have positive latent factors aligning with bond vectors (they buy those bonds) and others have negative alignment (they sell them). The `bond_bias` also captures whether a bond is generally in buy demand or sell pressure across the market.

When generating recommendations:
- For **offer** (you're selling) → recommend bonds with high positive predicted score (client is expected to buy)
- For **bid** (you're buying) → recommend bonds with high negative predicted score (client is expected to sell)

---

## Saving and Serving

```python
def save_model(model, path='mf_bond_factors/'):
    with open(f'{path}client_factors.json', 'w') as f:
        json.dump({c: list(v) for c, v in model.P.items()}, f)
    with open(f'{path}bond_factors.json', 'w') as f:
        json.dump({i: list(v) for i, v in model.Q.items()}, f)
    with open(f'{path}biases.json', 'w') as f:
        json.dump({
            'global_mean': model.global_mean,
            'client_bias': model.client_bias,
            'bond_bias':   model.bond_bias
        }, f)
```

At recommendation time:

```python
def recommend_mf(client_id, num=6):
    active_inventory = get_active_inventory_isins()
    eligible = mandate_filter(client_id, active_inventory)

    scores = {
        isin: model.predict(client_id, isin)
        for isin in eligible
    }

    return sorted(scores, key=scores.get, reverse=True)[:num]
```

---

## What the Latent Factors Capture

You can interpret latent factors by looking at which bonds have the highest and lowest values for each factor:

```python
for f in range(k):
    factor_scores = {isin: Q[isin][f] for isin in all_isins}
    top    = sorted(factor_scores, key=factor_scores.get, reverse=True)[:5]
    bottom = sorted(factor_scores, key=factor_scores.get)[:5]
    print(f"Factor {f}: High={[get_bond_desc(i) for i in top]}")
    print(f"            Low= {[get_bond_desc(i) for i in bottom]}")
```

Example output:
```
Factor 0: High=[Apple 2030, Microsoft 2029, Amazon 2031, ...] → "Investment grade Tech"
           Low= [Barclays Sub 2028, Deutsche Bank Sub 2027, ...] → "Subordinated Financials"
```

These interpretations are post-hoc — the model finds them automatically.

---

## Cold Start Problem

New clients have no factor vector. New bonds (new issues) have no factor vector. Options:

**For new clients:**
- Fall back to popularity or content-based for first 2–3 weeks
- Once the client has 5+ trades, train a one-off client vector (hold Q fixed, optimize P[client] only on their trades)

**For new bonds (new issues):**
- Initialize bond vector as the average of similar bonds (by sector/duration/rating)
- This is called a "warm start" — better than random initialization, and the model refines it as trades accumulate

---

## Strengths and Weaknesses

**Strengths:**
- Discovers non-obvious cross-bond preferences automatically
- Handles the full complexity of client taste in a compact representation
- Bias terms capture market-wide demand separately from individual preferences

**Weaknesses:**
- Cold start for new clients and new bonds
- Needs retraining as preferences shift (rolling retraining required)
- Difficult to explain to salespeople or clients ("the model says so" isn't a satisfying answer)
- Requires sufficient data — thin desks with few clients may not have enough to train well
