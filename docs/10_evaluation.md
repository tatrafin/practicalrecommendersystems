# 10 — Evaluation Framework

## Why Evaluation Matters

Every algorithm in this project makes different trade-offs. How do you know which one actually serves users best? You need a rigorous way to measure performance offline — before deploying anything to real users.

**Files:**
- `evaluator/evaluation_runner.py` — runs evaluations for each algorithm
- `evaluator/algorithm_evaluator.py` — metric implementations

---

## The Core Challenge: What Are We Measuring?

Recommendations can be evaluated in two ways:

| Type | Question | Metric |
|------|----------|--------|
| **Rating prediction** | How accurately does the model predict ratings? | MAE (Mean Absolute Error) |
| **Ranking quality** | Are the right items at the top of the list? | MAP, Recall@K |

Rating prediction accuracy (MAE) is easy to compute but doesn't reflect the real task. In practice, users see a ranked list — so getting the ranking right matters more than exact score prediction.

This project implements both.

---

## Data Splitting

Before evaluating, the dataset must be split into training and test sets — the model learns from training data and is evaluated on test data it has never seen.

### Hold-Out Split (70/30)

```python
def split_data(ratings, test_size=0.3):
    # Sort ratings by timestamp per user
    # Use older ratings for training, newer for testing
    train, test = [], []
    for user in users:
        user_ratings = sorted(ratings[user], key=lambda r: r.timestamp)
        split_point = int(len(user_ratings) * 0.7)
        train.extend(user_ratings[:split_point])
        test.extend(user_ratings[split_point:])
    return train, test
```

Using **temporal splitting** (oldest ratings = train, newest = test) is more realistic than random splitting, because in production you always predict future interactions from past history.

### Minimum Ratings Filter

```python
def clean_data(ratings, min_ratings=5):
    return {user: r for user, r in ratings.items() if len(r) >= min_ratings}
```

Users with very few ratings are excluded — there isn't enough data to make reliable predictions for them, and they would skew the metrics.

---

## Metric 1 — Mean Absolute Error (MAE)

Used when evaluating **rating prediction** algorithms (mainly neighborhood CF and content-based when used for score prediction).

```
MAE = (1/N) × Σ |predicted_rating(u, i) - actual_rating(u, i)|
```

For each user-item pair in the test set, compute the absolute difference between the predicted and actual rating, then average over all test pairs.

**Lower is better.** A MAE of 0.8 means predictions are off by 0.8 rating points on average (on a 1–10 scale).

```python
class MeanAverageError:
    def evaluate(self, recommender, test_ratings):
        errors = []
        for user_id, movie_id, actual in test_ratings:
            predicted = recommender.predict_score(user_id, movie_id)
            errors.append(abs(predicted - actual))
        return sum(errors) / len(errors)
```

---

## Metric 2 — Precision@K and Recall@K

Used when evaluating **ranking** algorithms. For each user, the algorithm produces a ranked top-K list. We check how many of the test items (items the user actually liked) appear in that list.

### Precision@K
```
Precision@K = (number of relevant items in top-K) / K
```
"Of the K things I showed, how many were actually good?"

### Recall@K
```
Recall@K = (number of relevant items in top-K) / (total relevant items for user)
```
"Of all the good things available, how many did I surface?"

### Average Precision@K (AP@K)
AP@K rewards algorithms that put relevant items near the **top** of the ranked list, not just anywhere in it:

```python
def average_precision_k(recommended, relevant, k):
    hits = 0
    score = 0.0
    for i, item in enumerate(recommended[:k]):
        if item in relevant:
            hits += 1
            score += hits / (i + 1)   # precision at position i
    return score / min(len(relevant), k)
```

For example, if the relevant items are at positions 1, 3, 5 (1-indexed):
- Precision at 1: 1/1 = 1.0
- Precision at 3: 2/3 = 0.67
- Precision at 5: 3/5 = 0.60
- AP@5 = (1.0 + 0.67 + 0.60) / 3 = 0.76

### Mean Average Precision (MAP)
Average AP@K across all users:
```
MAP@K = (1/|Users|) × Σ AP@K(user)
```

**Higher is better.** MAP = 1.0 means every user got perfect ranked lists.

---

## Running Evaluations

Each algorithm has a dedicated evaluation function:

```bash
python evaluator/evaluation_runner.py -pop    # Popularity baseline
python evaluator/evaluation_runner.py -cf     # Neighborhood CF
python evaluator/evaluation_runner.py -cb     # Content-based
python evaluator/evaluation_runner.py -funk   # Funk SVD
python evaluator/evaluation_runner.py -bpr    # BPR
python evaluator/evaluation_runner.py -fwls   # Hybrid FWLS
```

### What Each Evaluation Does

**CF Evaluation** — sweeps neighborhood size:
```python
for neighborhood_size in [5, 10, 15, 20, 25]:
    rec = NeighborhoodBasedRecs(neighborhood_size=neighborhood_size)
    map_score = evaluate(rec, test_data, k=10)
    print(f"K={neighborhood_size}: MAP={map_score:.4f}")
```

**Funk SVD Evaluation** — sweeps number of factors:
```python
for num_factors in [5, 10, 20, 40]:
    train_and_evaluate(num_factors, test_data)
```

**BPR Evaluation** — sweeps factors, uses Recall@K (ranking-focused):
```python
for k in [5, 10, 20, 50]:
    bpr = BayesianPersonalizationRanking(k=k)
    bpr.train(train_data)
    recall = recall_at_k(bpr, test_data, k=10)
```

---

## Interpreting Results

A typical result table might look like:

| Algorithm | MAP@10 | Recall@10 | MAE |
|-----------|--------|-----------|-----|
| Popularity | 0.05 | 0.08 | — |
| CF (k=15) | 0.12 | 0.18 | 1.2 |
| Content-Based | 0.09 | 0.14 | 1.4 |
| Funk SVD (k=20) | 0.16 | 0.22 | 0.9 |
| BPR (k=20) | 0.14 | 0.24 | — |
| FWLS | 0.18 | 0.25 | 0.8 |

Key observations to look for:
- Any personalized algorithm should beat popularity
- FWLS should outperform the individual base algorithms (if it doesn't, check that the feature functions are informative)
- BPR often wins on Recall even if Funk SVD wins on MAE (because BPR optimizes ranking, not score)

---

## Limitations of Offline Evaluation

Offline evaluation has known blind spots:

1. **Popularity bias in test data** — if the test set is dominated by popular movies, algorithms that favor popular items will appear better
2. **Missing negatives** — a movie not in the test set isn't necessarily bad; the user may just not have seen it
3. **No novelty/serendipity measurement** — a recommendation of obvious blockbusters might score high on MAP but provide no value to the user
4. **Temporal drift** — user tastes change; a model trained on old data may not reflect current preferences

For a complete picture, pair offline evaluation with **A/B testing** in a live environment — but that requires real users and a deployed system.

---

## Summary

| Metric | Best for | Lower/Higher = Better |
|--------|----------|----------------------|
| MAE | Rating prediction accuracy | Lower |
| Precision@K | Fraction of shown items that are relevant | Higher |
| Recall@K | Fraction of relevant items surfaced | Higher |
| MAP | Overall ranking quality | Higher |

Use the evaluation runner to understand each algorithm's strengths before choosing which to serve in production — or combine them with FWLS to get the best of all.
