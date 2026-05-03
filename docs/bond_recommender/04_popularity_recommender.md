# 04 — Popularity-Based Recommender

## What It Does

In the movie system, popularity means "most rated by all users." In fixed income, popularity means **market demand** — which bonds are clients most actively trading or inquiring about right now.

This is your baseline and your cold-start fallback. When you have no information about a client, show them what's hot in the market.

---

## Why It Still Matters in Fixed Income

In fixed income, market demand concentration is much stronger than in movies. On any given day:
- A few names dominate flow — often driven by an earnings release, rating action, or index rebalancing
- A newly issued bond (new issue) may account for 30–40% of all inquiries in its first week
- Risk-off events cause uniform selling across client types

Popularity recommendations capture this market-wide momentum and surface it to clients who haven't yet acted on it.

---

## Signal Sources

### Signal 1 — Most Traded by Count (Past 7 Days)

```python
def most_traded_bonds(days=7, num=10):
    cutoff = datetime.now() - timedelta(days=days)
    return (
        Trade.objects
        .filter(trade_timestamp__gte=cutoff)
        .values('isin')
        .annotate(trade_count=Count('trade_id'))
        .order_by('-trade_count')[:num]
    )
```

Raw count of trades — biased toward liquid names (many small trades inflate count).

### Signal 2 — Most Traded by Notional Volume

```python
def most_traded_by_volume(days=7, num=10):
    cutoff = datetime.now() - timedelta(days=days)
    return (
        Trade.objects
        .filter(trade_timestamp__gte=cutoff)
        .values('isin')
        .annotate(total_notional=Sum('notional'))
        .order_by('-total_notional')[:num]
    )
```

Volume-weighted — large block trades dominate. Better for illiquid markets where few large trades signal real demand.

### Signal 3 — Most Inquired (RFQ Count)

```python
def most_rfq_bonds(days=7, num=10):
    cutoff = datetime.now() - timedelta(days=days)
    return (
        RFQLog.objects
        .filter(rfq_timestamp__gte=cutoff)
        .values('isin')
        .annotate(rfq_count=Count('id'))
        .order_by('-rfq_count')[:num]
    )
```

Captures interest even when trades don't execute — useful for illiquid bonds where many clients are looking but deals are hard to complete.

### Signal 4 — Buy-Side Demand Specifically

```python
def most_bought(days=7, num=10):
    cutoff = datetime.now() - timedelta(days=days)
    return (
        Trade.objects
        .filter(trade_timestamp__gte=cutoff, direction='BUY')
        .values('isin')
        .annotate(buy_volume=Sum('notional'))
        .order_by('-buy_volume')[:num]
    )
```

Important distinction from movies: direction matters. A bond being sold by everyone is a very different signal than one being bought by everyone. Separate buy-side and sell-side popularity.

---

## Combined Popularity Score

In practice you combine these signals with weights:

```python
def popularity_score(isin, days=7):
    trade_vol   = get_trade_volume(isin, days)       # normalized 0–1
    rfq_count   = get_rfq_count(isin, days)          # normalized 0–1
    buy_volume  = get_buy_volume(isin, days)          # normalized 0–1

    # Weights tuned by desk — adjust based on what signals are most reliable
    score = (0.4 * trade_vol
           + 0.3 * rfq_count
           + 0.3 * buy_volume)
    return score
```

Normalize each signal to 0–1 range before combining, otherwise volume (in millions) will dominate count signals.

---

## Applying to Inventory

Popularity is only useful if the bond is in your inventory. The filter step:

```python
def popular_inventory_bonds(client_id, num=6, days=7):
    # 1. Score all bonds
    popular_bonds = compute_popularity_scores(days=days)

    # 2. Filter to current inventory
    active_axes = InventoryAxe.objects.filter(
        is_active=True,
        expiry__gt=datetime.now()
    ).values_list('isin', flat=True)

    # 3. Filter out what client already holds in size
    client_positions = ClientPosition.objects.filter(
        client_id=client_id,
        position_date=today()
    ).values_list('isin', flat=True)

    # 4. Apply mandate filter
    mandate_ok = get_mandate_compatible_isins(client_id)

    eligible = set(active_axes) & set(mandate_ok) - set(client_positions)

    return [b for b in popular_bonds if b['isin'] in eligible][:num]
```

---

## Segmented Popularity (by Client Type)

One enhancement over the movie baseline: you can segment popularity by **client type**. Insurance companies and hedge funds have very different appetites:

```python
def popularity_by_client_type(client_type, days=7, num=10):
    cutoff = datetime.now() - timedelta(days=days)
    return (
        Trade.objects
        .filter(
            trade_timestamp__gte=cutoff,
            client__client_type=client_type
        )
        .values('isin')
        .annotate(total_notional=Sum('notional'))
        .order_by('-total_notional')[:num]
    )
```

This means an insurance company sees what other insurance companies are trading — much more relevant than market-wide flow which is dominated by hedge fund activity.

---

## Sector and Duration Buckets

Fixed income clients think in terms of sectors and duration buckets, not individual bonds. A further refinement:

```python
def popular_in_sector_duration(sector, min_dur, max_dur, days=7):
    relevant_isins = BondCharacteristics.objects.filter(
        bond__sector=sector,
        duration__gte=min_dur,
        duration__lt=max_dur
    ).values_list('isin', flat=True)

    return (
        Trade.objects
        .filter(isin__in=relevant_isins, trade_timestamp__gte=cutoff)
        .values('isin')
        .annotate(total=Sum('notional'))
        .order_by('-total')[:10]
    )
```

For a client known to trade 5–7yr USD Financials, show them what's most active in that bucket.

---

## Strengths and Weaknesses

**Strengths:**
- Works with zero client history (cold start)
- Captures real-time market themes and momentum
- Easy to explain to sales ("this is the hottest paper in IG right now")
- Useful as a "market update" push to clients who haven't traded recently

**Weaknesses:**
- Not personalized — two very different clients get the same list
- Reinforces popular bonds further (popularity bias)
- Can miss idiosyncratic client preferences (e.g., a client who specifically likes niche sub-sectors)
- Direction-agnostic if not segmented (buy vs. sell popularity matter separately)

---

## Use in Practice

**Morning run distribution:** Every morning, a salesperson sends clients a "run" of bonds available for trading. The popularity recommender helps prioritize what goes at the top of that run — start with the most in-demand bonds to maximize hit rate.

**New client onboarding:** When a new client relationship is established and there's no trade history yet, popularity by client type is the best starting point.

**Market dislocation events:** During spread-widening events, use sell-side popularity (most sold) to identify what clients are offloading and reach out to potential buyers in your client base.
