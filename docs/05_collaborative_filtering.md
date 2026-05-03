# 05 — Neighborhood-Based Collaborative Filtering

## The Core Idea

Collaborative filtering (CF) is based on one simple observation: **people who agreed in the past tend to agree in the future**. If you and another user both loved the same five movies, you're likely to enjoy similar things going forward.

Item-based CF flips this around: instead of finding similar users, it finds **similar items**. For a given user, it looks at what they've already rated and finds items similar to those — weighted by both the similarity and how enthusiastically the user rated the reference item.

**Files:**
- Algorithm: `recs/neighborhood_based_recommender.py` — `NeighborhoodBasedRecs`
- Model builder: `builder/item_similarity_calculator.py` — `ItemSimilarityMatrixBuilder`

---

## Phase 1 — Building the Similarity Matrix (Offline)

Before any recommendation can be made, you need to compute item-to-item similarities. This is done once as a batch job.

### Step 1 — Normalize Ratings

Raw ratings vary by user. A user who always gives 9s and 10s is different from one who uses the full 1–10 scale. To make ratings comparable across users, each user's ratings are **z-score normalized**:

```
normalized_rating = (raw_rating - user_mean) / user_std_dev
```

This centers each user's ratings around zero and scales them by their variance. A rating of 8 from a tough critic now means the same as a rating of 8 from a generous one — relative to their own patterns.

### Step 2 — Build a Sparse User-Item Matrix

Each row is a user, each column is a movie, each cell is the normalized rating (or 0 if not rated). With tens of thousands of movies and thousands of users, this matrix is extremely sparse — most cells are empty.

`scipy.sparse` is used to store only the non-zero values efficiently.

### Step 3 — Compute Cosine Similarity Between Items

For two items A and B, cosine similarity measures how similar their rating vectors are:

```
sim(A, B) = (A · B) / (|A| × |B|)
```

Where `A` and `B` are columns of the user-item matrix (i.e., the vector of all users' ratings for each item).

- Result is between -1 and 1
- 1 means items are rated identically by all users who rated both
- 0 means no correlation
- -1 means opposite ratings

### Step 4 — Filter and Store

Not all similarities are meaningful. The builder applies two filters:

```python
min_overlap = 15    # at least 15 users must have rated both items
min_sim = 0.2       # similarity must exceed this threshold
```

Pairs that pass are stored in the `Similarity` table.

```bash
# Run the builder
python builder/item_similarity_calculator.py
```

---

## Phase 2 — Serving Recommendations (Online)

**Class:** `NeighborhoodBasedRecs`  
**Key parameters:** `neighborhood_size=15`, `min_sim=0.0`

### The Prediction Formula

For a target item `i` and user `u`, the predicted score is:

```
predicted_score(u, i) = mean_rating(u) + 
    Σ [ sim(i, j) × (rating(u, j) - mean_rating(u)) ]
    ─────────────────────────────────────────────────
              Σ |sim(i, j)|
```

Where the sum runs over all items `j` that:
- The user `u` has already rated
- Are similar to target item `i` (within the neighborhood)

In plain English: start with the user's average rating, then adjust up or down based on how they rated similar items.

### Recommendation Steps

```python
def recommend_items(self, user_id, num=6):
    # 1. Get all items the user has rated
    user_ratings = Rating.objects.filter(user_id=user_id)

    # 2. For each candidate item (not yet rated):
    #    - Find similar items the user HAS rated
    #    - Apply the weighted formula above
    #    - Store the predicted score

    # 3. Sort candidates by predicted score, return top-N
```

For each candidate movie, the algorithm:
1. Fetches its N most similar movies from the `Similarity` table
2. Checks which of those the user has rated
3. Computes the weighted prediction
4. Ranks all candidates

---

## API Endpoint

```
GET /recommender/cf/{user_id}/
```

```python
def recs_cf(request, user_id):
    rec = NeighborhoodBasedRecs()
    recs_list = rec.recommend_items(user_id, num=6)
    return JsonResponse({'recs': recs_list})
```

---

## Similar Users (Bonus Feature)

The `recommender/views.py` also has an endpoint that finds similar users directly:

```
GET /recommender/similar_users/{user_id}/
```

It computes both **Pearson correlation** and **Jaccard similarity** between users based on their rating vectors. This is user-based CF, but it's shown as an analytics feature rather than used for recommendations (item-based CF scales better).

---

## Why Item-Based Over User-Based?

| | User-Based CF | Item-Based CF |
|--|--------------|---------------|
| Similarity computation | Between users | Between items |
| Scales with | # users | # items |
| Stability | Changes as users rate more | Items are stable |
| Interpretability | "People like you liked..." | "Because you liked X..." |

Item catalogs are typically smaller and more stable than user bases, making item-based CF more practical at scale.

---

## Strengths and Weaknesses

**Strengths:**
- Personalized — different recommendations per user
- Explainable — "recommended because you liked Movie X"
- No need to understand item content

**Weaknesses:**
- **Cold start** — new users with no ratings get no recommendations
- **Data sparsity** — with few ratings, similarities are unreliable
- **Popularity bias** — popular items get more co-ratings, so similarities skew popular

---

## Evaluate

```bash
python evaluator/evaluation_runner.py -cf
```

The evaluator sweeps over neighborhood sizes and reports MAP and Recall@K for each. This helps you find the optimal `neighborhood_size` parameter.

---

## Next

Content-based filtering addresses the cold start problem for items by using movie descriptions instead of ratings. See `06_content_based_recommender.md`.
