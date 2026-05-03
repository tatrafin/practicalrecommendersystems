# 05 — Collaborative Filtering for Bonds

## The Core Idea

"Clients who traded the same bonds tend to have similar tastes." Collaborative filtering identifies clients with overlapping trading histories and uses that similarity to surface bonds one client traded that the other hasn't seen yet.

In fixed income, this is a strong signal because institutional clients cluster naturally: insurance companies run similar liability-driven strategies, asset managers benchmark to the same indices, hedge funds share macro views. If two pension funds have bought the same ten bonds over the past month, the eleventh bond one of them just bought is a strong candidate for the other.

---

## Building the Client-Bond Interaction Matrix

The equivalent of the user-item rating matrix in MovieGEEK.

**Rows:** Clients  
**Columns:** Bond ISINs  
**Cell value:** Interaction signal for that client-bond pair

### Constructing the Signal

Unlike a 1–10 movie rating, you need to construct a signal from trade data. A reasonable approach:

```python
def interaction_signal(client_id, isin, days=7):
    trades = Trade.objects.filter(
        client_id=client_id,
        isin=isin,
        trade_timestamp__gte=cutoff(days)
    )

    if not trades.exists():
        return 0.0

    total_notional = trades.aggregate(Sum('notional'))['notional__sum']
    num_trades     = trades.count()
    direction_sign = +1 if trades.last().direction == 'BUY' else -1

    # Larger trades = stronger signal; multiple trades = even stronger
    raw_signal = log1p(total_notional / 1_000_000) * sqrt(num_trades)

    return direction_sign * raw_signal
```

Key choices:
- **Log-scale notional** — prevents a single $500M trade from overwhelming everything
- **Square root of trade count** — multiple trades increase signal but with diminishing returns
- **Direction sign** — positive for buys, negative for sells. This lets the model learn that clients who are selling a bond are different from clients buying it

### Normalization

As in the movie system, normalize per client using z-score before computing similarities:

```python
def normalize_signals(client_signals):
    mean = np.mean(client_signals)
    std  = np.std(client_signals)
    if std == 0:
        return {isin: 0 for isin in client_signals}
    return {isin: (v - mean) / std for isin, v in client_signals.items()}
```

---

## Item-Item CF (Bond Similarity from Client Co-trading)

The approach mirrors MovieGEEK's `ItemSimilarityMatrixBuilder`. Two bonds are similar if clients tend to trade them together.

```python
def build_bond_similarity_from_trades():
    # Build sparse client-bond matrix
    matrix = build_sparse_matrix()   # shape: (num_clients, num_bonds)

    # Cosine similarity between bond columns
    bond_sim = cosine_similarity(matrix.T)   # shape: (num_bonds, num_bonds)

    # Filter: minimum 5 clients must have traded both bonds
    # Filter: similarity > 0.15
    for i, j in pairs_above_threshold(bond_sim, min_overlap=5, min_sim=0.15):
        BondSimilarity.objects.create(
            source_isin=bond_ids[i],
            target_isin=bond_ids[j],
            similarity=bond_sim[i, j],
            similarity_type='co_trading'
        )
```

**Lower overlap threshold than movies (5 vs. 15):** Bond trading is sparser. Five clients having traded both bonds is meaningful in fixed income.

### Prediction for a Client

```python
def predict_score_cf(client_id, target_isin, neighborhood_size=10):
    client_trades = get_client_signals(client_id)  # {isin: signal}

    # Find bonds the client has traded that are similar to target
    similar_bonds = BondSimilarity.objects.filter(
        source_isin=target_isin,
        similarity_type='co_trading'
    ).order_by('-similarity')[:neighborhood_size]

    numerator   = 0.0
    denominator = 0.0

    for sim_bond in similar_bonds:
        if sim_bond.target_isin in client_trades:
            client_signal = client_trades[sim_bond.target_isin]
            numerator   += sim_bond.similarity * client_signal
            denominator += abs(sim_bond.similarity)

    if denominator == 0:
        return 0.0

    return numerator / denominator
```

This is the same weighted formula as MovieGEEK's neighborhood CF, but using trade signals instead of movie ratings.

---

## Client-Client CF (Who Trades Like This Client?)

For understanding and analytics, client-level similarity is also useful. You can answer: "Which other clients behave most like this one?"

```python
def compute_client_similarity(client_a, client_b):
    signals_a = get_normalized_signals(client_a)
    signals_b = get_normalized_signals(client_b)

    # Only bonds traded by both
    common_isins = set(signals_a.keys()) & set(signals_b.keys())
    if len(common_isins) < 3:
        return 0.0   # not enough overlap

    vec_a = [signals_a[isin] for isin in common_isins]
    vec_b = [signals_b[isin] for isin in common_isins]

    return cosine_similarity_1d(vec_a, vec_b)
```

Client similarity is stored in `ClientSimilarity` and surfaced in the analytics dashboard — useful for salespeople to understand client clustering.

**Pearson vs. Cosine:**
- **Cosine** is preferred when clients trade very different notional sizes (a $1B fund vs. a $50M fund — normalize for size before comparing)
- **Pearson** is preferred when you want to account for directional agreement (both bought X and sold Y together)

---

## Direction-Aware CF

A critical difference from movie recommendations: a client who sold a bond is a very different signal from one who bought it. A naive similarity computation ignores this.

One approach: build **separate** buy-signal and sell-signal matrices and compute similarities on each independently.

```python
def build_buy_matrix():
    return build_sparse_matrix(direction='BUY')

def build_sell_matrix():
    return build_sparse_matrix(direction='SELL')

buy_sim  = cosine_similarity(buy_matrix.T)
sell_sim = cosine_similarity(sell_matrix.T)
```

When recommending to a client:
- If the client's recent trades are predominantly BUY → use buy similarity to find bonds other buyers traded
- If predominantly SELL → use sell similarity to find what other sellers are offloading

---

## Inventory and Mandate Filtering

After scoring all candidate bonds with CF, apply the same filtering pipeline as the popularity recommender:

```python
def recommend_cf(client_id, num=6):
    # Score all inventory bonds
    active_inventory = get_active_inventory_isins()
    scores = {
        isin: predict_score_cf(client_id, isin)
        for isin in active_inventory
    }

    # Filter by mandate
    eligible = mandate_filter(client_id, scores.keys())

    # Exclude what client already holds significantly
    eligible -= concentrated_positions(client_id)

    return sorted(eligible, key=lambda i: scores[i], reverse=True)[:num]
```

---

## Handling Data Sparsity

Bond trading is sparse. A client may trade 20 bonds per week out of a universe of 5,000+ IG bonds. Strategies to mitigate:

1. **Issuer-level aggregation** — if a client has traded Apple 2027, treat it as a signal for all Apple bonds, not just that specific issue
2. **Sector-level fallback** — if direct bond overlap is too sparse, fall back to sector-level similarity
3. **Extend the lookback window** — use 30-day or 90-day history for clients who don't trade frequently
4. **Minimum overlap guard** — if fewer than 3 bonds overlap between two clients, don't compute similarity (return 0)

---

## Strengths and Weaknesses

**Strengths:**
- Captures latent client preferences without needing bond descriptions
- Works across issuers — can discover cross-sector patterns a salesperson wouldn't notice
- Explainable: "clients with similar portfolios to yours have been buying this bond"

**Weaknesses:**
- Sparse data — thin trade histories limit similarity quality
- Direction-insensitive unless explicitly handled
- New clients (no history) get no recommendations (cold start)
- Issuer concentration — popular issuers dominate co-trading patterns

---

## Run the Builder

```python
# In builder/bond_similarity_calculator.py
if __name__ == '__main__':
    build_bond_similarity_from_trades(days=30, min_overlap=5, min_sim=0.15)
    build_client_similarity(days=30, min_overlap=3)
```

Re-run weekly (or daily for active desks) as trade history accumulates.
