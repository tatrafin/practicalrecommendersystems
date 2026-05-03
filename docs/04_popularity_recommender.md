# 04 — Popularity-Based Recommender

## What It Is

The popularity recommender is the simplest possible algorithm: recommend whatever is most popular to everyone. It requires no knowledge of the individual user and no model training. It serves as a **baseline** — if a more complex algorithm can't beat this, something is wrong.

**File:** `recs/popularity_recommender.py`  
**Class:** `PopularityBasedRecs`

---

## How It Works

There are three variants depending on what data is available:

### Variant 1 — Most Rated (from Ratings table)

```python
def recommend_items_by_ratings(self, user_id, num=6):
    ratings = Rating.objects.filter(
        rating__gte=MIN_RATING
    ).values('movie_id').annotate(
        Count('movie_id')
    ).order_by('-movie_id__count')[:num]
```

1. Queries the `Rating` table
2. Filters to ratings above a minimum threshold
3. Groups by `movie_id` and counts how many users rated each movie
4. Returns the top-N most-rated movies

### Variant 2 — Most Purchased (from Logs table)

```python
def recommend_items_from_log(self, user_id, num=6):
    logs = Log.objects.filter(
        event='buy'
    ).values('content_id').annotate(
        Count('content_id')
    ).order_by('-content_id__count')[:num]
```

- Uses `collector_log` instead of ratings
- Counts "buy" events rather than explicit ratings
- Represents implicit feedback popularity

### Variant 3 — Highest Average Rating

- Ranks by average rating rather than count
- Biased toward movies with few but high ratings, so less reliable with sparse data

---

## Personalization Attempt

Despite being a non-personalized method, the class does filter out movies the user has already rated:

```python
def recommend_items(self, user_id, num=6):
    already_rated = Rating.objects.filter(user_id=user_id).values('movie_id')
    popular = self.get_popular_items(num + len(already_rated))
    return [m for m in popular if m not in already_rated][:num]
```

This is a minimal courtesy — don't recommend what the user has seen — but the ranking itself is global.

---

## API Endpoint

```
GET /recommender/pop/{user_id}/
```

Handled in `recommender/views.py`:

```python
def recs_pop(request, user_id):
    rec = PopularityBasedRecs()
    recs_list = rec.recommend_items(user_id, num=6)
    return JsonResponse({'recs': recs_list})
```

---

## When to Use It

| Situation | Use popularity? |
|-----------|----------------|
| New user (no history) | Yes — cold start problem |
| New item (no ratings) | No — won't appear until rated |
| Sparse data | Yes — works even with very few ratings |
| Dense data, personalization needed | No — use CF or MF instead |

Popularity recommendations are especially useful on **home pages**, **onboarding flows**, and **email newsletters** where you need to show something to everyone without knowing much about them.

---

## Strengths and Weaknesses

**Strengths:**
- Zero training time
- Always produces results (no cold-start failure)
- Easy to understand and debug
- Useful as a fallback when personalized models fail

**Weaknesses:**
- Same recommendations for everyone (no personalization)
- Popular items get more popular (popularity bias / filter bubble)
- Ignores individual taste entirely

---

## Evaluating the Baseline

```bash
python evaluator/evaluation_runner.py -pop
```

This gives you MAP and Recall@K scores. Any personalized algorithm must beat these numbers to justify its added complexity.

---

## Key Takeaway

Think of popularity recommendations as "what everyone else liked." It works surprisingly well in practice because popular items are popular for a reason. But as soon as you have enough user history, you can do better with collaborative filtering (see `05_collaborative_filtering.md`).
