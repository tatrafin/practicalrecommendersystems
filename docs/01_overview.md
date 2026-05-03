# 01 — Project Overview

## What Is MovieGEEK?

MovieGEEK is a movie recommendation web application built with Django. It serves as a practical learning environment for recommendation system algorithms. The app lets users browse movies, log interactions, and receive personalized recommendations through several distinct algorithms — from simple popularity rankings to sophisticated hybrid models.

This project accompanies the book *Practical Recommender Systems* and is designed so you can swap algorithms in and out and compare their behavior.

---

## Architecture at a Glance

```
┌─────────────────────────────────────────────────────┐
│                   Django Web App                    │
│  moviegeeks │ collector │ recommender │ analytics   │
└────────────────────────┬────────────────────────────┘
                         │
              ┌──────────▼──────────┐
              │      Database       │
              │  Movies, Ratings,   │
              │  Logs, Similarities │
              └──────────┬──────────┘
                         │
         ┌───────────────┼───────────────┐
         ▼               ▼               ▼
      builder/         recs/         evaluator/
   (train models)  (serve recs)   (measure quality)
```

### Django Apps

| App | Role |
|-----|------|
| `moviegeeks` | Movie catalog — browse, search, detail pages |
| `collector` | Logs user events (views, purchases) |
| `recommender` | JSON API endpoints that return recommendations |
| `analytics` | Dashboards for ratings, clusters, LDA topics |

### Supporting Modules

| Module | Role |
|--------|------|
| `builder/` | Trains and pre-computes recommendation models |
| `recs/` | Algorithm classes used at request time |
| `evaluator/` | Offline evaluation (MAP, Recall, MAE) |

---

## Recommendation Algorithms

Six algorithms are implemented, ordered from simplest to most complex:

| # | Algorithm | Type | File |
|---|-----------|------|------|
| 1 | Popularity | Non-personalized | `recs/popularity_recommender.py` |
| 2 | Neighborhood-Based CF | Collaborative Filtering | `recs/neighborhood_based_recommender.py` |
| 3 | Content-Based (LDA) | Content-Based | `recs/content_based_recommender.py` |
| 4 | Funk SVD | Matrix Factorization | `recs/funksvd_recommender.py` |
| 5 | BPR | Ranking / Implicit Feedback | `recs/bpr_recommender.py` |
| 6 | FWLS | Hybrid Ensemble | `recs/fwls_recommender.py` |

---

## Data Flow

```
1. Populate DB         populate_moviegeek.py → movies, genres
   (one-time setup)    populate_ratings.py   → user ratings
                       populate_logs.py      → interaction events

2. Train models        builder/ scripts      → similarity tables,
   (offline batch)                             factor matrices,
                                               LDA topic model

3. Serve recs          recs/ classes         → called by recommender/views.py
   (at request time)                           returns ranked item list

4. Evaluate            evaluator/            → offline metrics
   (optional)                                  over held-out data
```

---

## Running the App

```bash
# 1. Apply database migrations
python manage.py migrate --run-syncdb

# 2. Populate data (see 02_getting_data.md)
python populate_moviegeek.py
python populate_ratings.py
python populate_logs.py

# 3. Start the server
python manage.py runserver 127.0.0.1:8000
```

Open `http://127.0.0.1:8000` in your browser.

---

## File Map (Key Files Only)

```
practicalrecommendersystems/
├── manage.py                          Django entry point
├── prs_project/settings.py            App configuration, DB settings
├── populate_moviegeek.py              Load movie catalog
├── populate_ratings.py                Load user ratings
├── populate_logs.py                   Generate interaction logs
│
├── moviegeeks/
│   ├── models.py                      Movie, Genre models
│   └── views.py                       Browse/search views
│
├── collector/
│   ├── models.py                      Log model
│   └── views.py                       Event logging endpoint
│
├── recommender/
│   ├── models.py                      Similarity, Recs, SeededRecs
│   └── views.py                       API endpoints for all algorithms
│
├── analytics/
│   ├── models.py                      Rating, Cluster models
│   └── views.py                       Analytics dashboards
│
├── recs/                              Algorithm implementations
├── builder/                           Offline model training
└── evaluator/                         Evaluation framework
```

---

## Next Steps

- **02_getting_data.md** — How to download and load sample data
- **03_data_models.md** — Database schema in detail
- **04_popularity_recommender.md** — Simplest algorithm first
