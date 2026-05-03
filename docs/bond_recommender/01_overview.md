# 01 — Overview: Recommending IG Corporate Bonds

## Business Context

You are a dealer (bank or broker-dealer) with an inventory of Investment Grade (IG) corporate bonds. Your salespeople cover a book of institutional clients — asset managers, insurance companies, pension funds, and hedge funds. The goal is simple:

> **Match the right bond from your inventory to the right client at the right time.**

Done well, this increases inventory turnover, deepens client relationships, and generates more trading revenue. Done poorly, you blast irrelevant axes to everyone and train clients to ignore you.

A recommender system brings discipline and scale to this matching process.

---

## The Movie → Bond Analogy

The MovieGEEK system recommends movies to users. The mapping to fixed income is direct:

| MovieGEEK concept | Bond recommender equivalent |
|-------------------|-----------------------------|
| Movie | IG Corporate Bond (ISIN/CUSIP) |
| User | Client (fund, portfolio, desk) |
| Rating (1–10) | Trade size × direction (buy/sell) |
| View event | RFQ sent, bond looked up, price request |
| Genre | Sector (Financials, Industrials, Utilities) |
| Movie description | Bond characteristics (tenor, rating, spread, issuer) |
| Inventory (movies available) | Dealer inventory / axes |
| Recommendation | "We have this bond — you should look at it" |

---

## The Recommendation Problem in Fixed Income

### What makes it harder than movies

1. **Inventory constraint** — you can only recommend bonds you actually have (or can source). Unlike Netflix, the catalog changes daily.
2. **Directionality** — a client may want to buy or sell. Recommending a buy to a client who needs to reduce risk is worse than no recommendation.
3. **Position-awareness** — a client who already holds 5% of a bond's issue size won't buy more regardless of how good the match looks.
4. **Regulatory constraints** — suitability rules mean you cannot recommend instruments that don't fit the client's mandate.
5. **Market context** — spread widening, credit events, rate moves all affect appetite in ways a pure collaborative filter won't capture.
6. **Sparse data** — a large client may trade 50–100 bonds a week. A small client may trade 5. Movie users rate hundreds of films.

### What makes it tractable

- Bond characteristics are well-structured (rating, sector, duration, spread, issuer)
- Institutional clients have stable mandates (IG only, no financials, max 7yr duration)
- Past trades are a strong signal — a client who bought 5yr Financials last week will likely be interested in similar paper
- Inventory is known in advance — you can pre-compute fits

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Data Sources                         │
│  Positions Feed │ Trade History │ Inventory/Axes        │
│  Bond Analytics │ Market Data   │ Client Mandates       │
└───────────────────────┬─────────────────────────────────┘
                        │
          ┌─────────────▼──────────────┐
          │     Feature Engineering    │
          │  Client profiles           │
          │  Bond fingerprints         │
          │  Interaction signals       │
          └─────────────┬──────────────┘
                        │
        ┌───────────────┼────────────────┐
        ▼               ▼                ▼
   Popularity        CF / MF         Content-Based
   (market demand)  (similar        (bond characteristics)
                    clients)
        └───────────────┼────────────────┘
                        ▼
                  Hybrid (FWLS)
                        │
                        ▼
            Inventory Filter & Mandate Check
                        │
                        ▼
              Ranked Axes per Client
```

---

## Six Algorithms Applied

| # | Algorithm | Bond use case |
|---|-----------|---------------|
| 1 | Popularity | Most actively traded or most client-inquired bonds today |
| 2 | Neighborhood CF | Clients with similar portfolios bought/sold these bonds |
| 3 | Content-Based | Bonds with similar characteristics to what this client traded |
| 4 | Matrix Factorization | Latent client risk/duration/sector preferences from trade history |
| 5 | BPR | Rank bonds by RFQ activity and inquiry signals (implicit feedback) |
| 6 | FWLS Hybrid | Combine all signals, weight by data richness of each client |

---

## Two Recommendation Scenarios

### Scenario A — Push: "We have this bond, who wants it?"
You have a position to move. The system scores every client and surfaces the top matches. The salesperson reaches out proactively.

### Scenario B — Pull: "This client is active, what should we show them?"
A client has been trading recently. The system scans your inventory and surfaces the best fits based on their recent activity and current portfolio.

Both scenarios are supported — they are the same ranking problem viewed from opposite ends.

---

## Document Map

- **02_data_sources.md** — What data you need and where it comes from
- **03_data_models.md** — Schema design for bonds, clients, trades, inventory
- **04_popularity_recommender.md** — Market demand signals
- **05_collaborative_filtering.md** — Client similarity from trade behavior
- **06_content_based_recommender.md** — Bond characteristic matching
- **07_matrix_factorization.md** — Latent preference learning
- **08_bpr_recommender.md** — Implicit signal ranking
- **09_hybrid_recommender.md** — Combining all algorithms
- **10_practical_considerations.md** — Risk, compliance, and operational notes
