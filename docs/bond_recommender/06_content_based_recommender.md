# 06 — Content-Based Recommender for Bonds

## The Core Idea

Content-based filtering recommends bonds **structurally similar** to what a client has recently traded — based on the bond's own characteristics, not what other clients did. A client who bought 5-year A-rated USD Financials last week likely wants to see more 5-year A-rated USD Financials.

This is the most natural approach for fixed income. Institutional clients have mandates, benchmarks, and risk budgets that constrain them to specific sectors, rating buckets, and duration ranges. Bond characteristics capture these constraints precisely.

**Unlike the movie system where content = text descriptions and LDA topics, here content = quantitative bond characteristics.** No text processing is needed — the features are structured numbers and categories already.

---

## Bond Feature Vector

Each bond is represented as a vector of normalized features:

```python
def bond_feature_vector(isin):
    bond = Bond.objects.get(isin=isin)
    chars = BondCharacteristics.objects.get(isin=isin)

    return {
        # Structural features
        'duration':         chars.duration,               # years, e.g. 4.8
        'rating_numeric':   bond.rating_numeric,          # 1=AAA to 10=BBB-
        'oas_bps':          chars.oas_bps,                # spread, e.g. 142
        'coupon':           bond.coupon,                  # e.g. 3.85
        'issue_size_log':   log10(bond.issue_size),       # log-scaled

        # Categorical features (one-hot encoded)
        'sector_financials': 1 if bond.sector == 'Financials' else 0,
        'sector_industrials': 1 if bond.sector == 'Industrials' else 0,
        'sector_utilities':   1 if bond.sector == 'Utilities' else 0,
        # ... all sectors

        'currency_usd':    1 if bond.currency == 'USD' else 0,
        'currency_eur':    1 if bond.currency == 'EUR' else 0,
        'coupon_fixed':    1 if bond.coupon_type == 'Fixed' else 0,
        'seniority_senior': 1 if 'Senior' in bond.seniority else 0,
    }
```

**Key choices:**
- `log10(issue_size)` — a $5B issue vs. a $500M issue matters but not by 10x; log-scale compresses the range
- `rating_numeric` — converts letter ratings to ordinal numbers so distance has meaning
- One-hot encoding for sectors — sector A and sector B are not "close to" sector C in between them

---

## Normalizing Features

Different features have very different scales (duration is 0–30, OAS is 0–1000). Normalize all numerical features to zero mean and unit variance before computing similarity:

```python
from sklearn.preprocessing import StandardScaler

feature_matrix = np.array([bond_feature_vector(isin) for isin in all_isins])
scaler = StandardScaler()
normalized_matrix = scaler.fit_transform(feature_matrix)
```

Save the scaler — you'll need it to normalize new bonds in the same space.

---

## Computing Bond-Bond Similarity

With normalized feature vectors, cosine similarity measures structural closeness:

```python
from sklearn.metrics.pairwise import cosine_similarity

sim_matrix = cosine_similarity(normalized_matrix)  # shape: (N, N)

for i, isin_a in enumerate(all_isins):
    for j, isin_b in enumerate(all_isins):
        if i != j and sim_matrix[i, j] > 0.7:  # high threshold for bonds
            BondSimilarity.objects.create(
                source_isin=isin_a,
                target_isin=isin_b,
                similarity=sim_matrix[i, j],
                similarity_type='characteristics'
            )
```

**Higher threshold (0.7) than the movie system (0.2):** Bond feature spaces are dense and structured, so similarities cluster high. A threshold of 0.7 filters to genuinely similar bonds.

---

## Building a Client Profile

The client's profile is a weighted average of the feature vectors of the bonds they've recently traded:

```python
def build_client_profile(client_id, days=7):
    trades = Trade.objects.filter(
        client_id=client_id,
        trade_timestamp__gte=cutoff(days),
        direction='BUY'   # build profile from what they're buying
    )

    if not trades.exists():
        return None  # no buy history — content-based can't help

    total_notional = sum(t.notional for t in trades)
    profile_vector = np.zeros(NUM_FEATURES)

    for trade in trades:
        weight = trade.notional / total_notional   # larger trades = more weight
        bond_vec = get_normalized_feature_vector(trade.isin)
        profile_vector += weight * bond_vec

    return profile_vector   # weighted centroid of traded bonds
```

The profile vector represents the "ideal bond" for this client based on recent activity. Bonds close to this centroid in feature space are strong candidates.

---

## Scoring Candidate Bonds

```python
def score_bond_for_client(client_profile, target_isin):
    target_vec = get_normalized_feature_vector(target_isin)
    return cosine_similarity(
        client_profile.reshape(1, -1),
        target_vec.reshape(1, -1)
    )[0][0]

def recommend_content_based(client_id, num=6):
    profile = build_client_profile(client_id)
    if profile is None:
        return []   # fall back to popularity

    active_inventory = get_active_inventory_isins()
    already_traded   = get_recently_traded_isins(client_id)
    eligible         = mandate_filter(client_id, active_inventory) - already_traded

    scores = {
        isin: score_bond_for_client(profile, isin)
        for isin in eligible
    }

    return sorted(scores, key=scores.get, reverse=True)[:num]
```

---

## Directional Profiles (Buy vs. Sell)

Because clients buy and sell bonds for different reasons, build separate profiles:

```python
buy_profile  = build_client_profile(client_id, direction='BUY')
sell_profile = build_client_profile(client_id, direction='SELL')
```

When recommending bonds from your **offer** inventory (you want to sell), match against the client's buy profile.  
When looking for **bid** opportunities (you want to buy from client), match against their sell profile.

---

## Sector + Duration Buckets (Simpler Alternative)

For a quick implementation without full vector similarity, discretize the key dimensions:

```python
def get_client_bucket_preference(client_id, days=7):
    trades = Trade.objects.filter(client_id=client_id, direction='BUY',
                                  trade_timestamp__gte=cutoff(days))

    bucket_counts = defaultdict(int)
    for trade in trades:
        chars = BondCharacteristics.objects.get(isin=trade.isin)
        bond  = Bond.objects.get(isin=trade.isin)
        dur_bucket = round(chars.duration)   # e.g. 5 for "5yr"
        bucket_counts[(bond.sector, dur_bucket)] += trade.notional

    # Return top 3 buckets by notional
    return sorted(bucket_counts, key=bucket_counts.get, reverse=True)[:3]

def recommend_by_bucket(client_id, num=6):
    preferred_buckets = get_client_bucket_preference(client_id)

    recommendations = []
    for sector, dur in preferred_buckets:
        matching_inventory = (
            InventoryAxe.objects
            .filter(is_active=True)
            .filter(bond__sector=sector)
            .filter(bondcharacteristics__duration__gte=dur - 0.5)
            .filter(bondcharacteristics__duration__lt=dur + 0.5)
            .order_by('-urgency')[:3]
        )
        recommendations.extend(matching_inventory)

    return recommendations[:num]
```

Bucket-based is less precise but more interpretable and requires no pre-computed similarity tables.

---

## Feature Importance for Fixed Income Clients

Not all features matter equally. Based on how institutional clients actually make decisions:

| Feature | Importance | Why |
|---------|-----------|-----|
| Sector | Very high | Mandates often sector-specific |
| Duration | Very high | Duration budgets are hard constraints |
| Credit rating | High | IG mandates have rating floors |
| Currency | High | Currency-matched to liabilities |
| OAS / spread | Medium | Entry-point sensitivity |
| Issuer | Medium | Issuer concentration limits |
| Coupon type | Low | Fixed vs. float matters for some |
| Seniority | Low | Most IG investors prefer Sr Unsecured |

Weight the feature vector accordingly if you want to emphasize what matters most. Multiply each feature by its importance weight before computing cosine similarity.

---

## Strengths and Weaknesses

**Strengths:**
- Works for new bonds — as long as characteristics are available, a new issue can be recommended immediately
- Handles clients with narrow mandates naturally — the mandate is essentially pre-baked into their profile
- Explainable: "We recommend this because it matches your recent activity in 5yr USD Financials"
- No need for other clients' data

**Weaknesses:**
- New client cold start — if a client has no trades, there's no profile to build
- Over-specialization — if a client always buys 5yr Financials, that's all they'll ever see
- Doesn't capture cross-sector opportunities a sophisticated investor might want
- Feature engineering is manual — someone has to decide which bond attributes matter
