# 09 — Hybrid Recommender (FWLS)

## The Core Idea

No single recommendation algorithm is best in all situations. CF works well with dense data but fails for new users. Content-based handles new items but over-specializes. Matrix factorization is powerful but opaque.

**Feature-Weighted Linear Stacking (FWLS)** combines multiple algorithms into a single ensemble. It uses linear regression to learn the optimal weights for each algorithm — and crucially, those weights can **vary depending on context** (e.g., how much data we have about the user).

**Files:**
- Algorithm: `recs/fwls_recommender.py` — `FeatureWeightedLinearStacking`
- Model builder: `builder/fwls_calculator.py` — `FWLSCalculator`

---

## The Architecture

FWLS is a **meta-learner**: it sits on top of two base algorithms and combines their predictions.

```
User request
    │
    ├── ContentBasedRecs.predict_score(u, i)   ──► cb_score
    │
    ├── NeighborhoodBasedRecs.predict_score(u, i) ► cf_score
    │
    └── FWLS
           │
           │  predicted = w_cb1 × cb_score × feature1(u, i)
           │            + w_cb2 × cb_score × feature2(u, i)
           │            + w_cf1 × cf_score × feature1(u, i)
           │            + w_cf2 × cf_score × feature2(u, i)
           │
           └── final recommendation score
```

The weights `w_cb1`, `w_cb2`, `w_cf1`, `w_cf2` are learned from historical ratings.

---

## Feature Functions

Feature functions encode **context about the user-item pair**. They modulate how much each algorithm's prediction should be trusted:

```python
def fun1(user_id, movie_id):
    return 1.0   # constant — always apply this weight

def fun2(user_id, movie_id):
    num_ratings = Rating.objects.filter(user_id=user_id).count()
    return 1.0 if num_ratings > 3 else 0.0
```

- `fun1` — a baseline feature that's always active
- `fun2` — activates only when the user has rated more than 3 movies

So for a new user with only 1 rating, `fun2` returns 0 — effectively disabling the CF components that depend on sufficient history. For an experienced user, both features are active and the model can rely more on CF.

This is the "feature-weighted" part: the same algorithm gets different weights depending on the context.

---

## Training the FWLS Model

### Step 1 — Generate Training Data

For each rating in the training set, compute what each base algorithm would have predicted:

```python
for user_id, movie_id, actual_rating in training_ratings:
    cb_score = content_based.predict_score(user_id, movie_id)
    cf_score = neighborhood_cf.predict_score(user_id, movie_id)

    # Build feature vector
    row = [
        cb_score * fun1(user_id, movie_id),   # cb1
        cb_score * fun2(user_id, movie_id),   # cb2
        cf_score * fun1(user_id, movie_id),   # cf1
        cf_score * fun2(user_id, movie_id),   # cf2
    ]
    X.append(row)
    y.append(actual_rating)
```

### Step 2 — Fit Linear Regression

```python
from sklearn.linear_model import LinearRegression

model = LinearRegression(fit_intercept=False)
model.fit(X, y)

weights = model.coef_
# e.g. [0.3, 0.5, 0.1, 0.6]
# meaning: cb1=0.3, cb2=0.5, cf1=0.1, cf2=0.6
```

### Step 3 — Save Weights

```python
import pickle
with open('fwls_parameters.data', 'wb') as f:
    pickle.dump(weights, f)
```

### Run Training

```bash
python builder/fwls_calculator.py
```

This requires the LDA model and item similarity to already be built (content-based and CF must work first).

---

## Serving Recommendations

```python
class FeatureWeightedLinearStacking:
    def __init__(self):
        self.weights = load_weights('fwls_parameters.data')
        self.cb = ContentBasedRecs()
        self.cf = NeighborhoodBasedRecs()

    def predict_score(self, user_id, movie_id):
        cb_score = self.cb.predict_score(user_id, movie_id)
        cf_score = self.cf.predict_score(user_id, movie_id)

        features = [
            cb_score * fun1(user_id, movie_id),
            cb_score * fun2(user_id, movie_id),
            cf_score * fun1(user_id, movie_id),
            cf_score * fun2(user_id, movie_id),
        ]

        return dot(self.weights, features)

    def recommend_items(self, user_id, num=6):
        already_rated = get_rated_movies(user_id)
        scores = {
            movie_id: self.predict_score(user_id, movie_id)
            for movie_id in candidate_movies
            if movie_id not in already_rated
        }
        return sorted(scores, key=scores.get, reverse=True)[:num]
```

---

## API Endpoint

```
GET /recommender/fwls/{user_id}/
```

---

## Why Linear Stacking?

Linear stacking (also called **linear blending**) is a simple but powerful form of ensemble learning. It assumes the optimal prediction is a linear combination of the base predictions:

```
final_score = w1 × algo1_score + w2 × algo2_score + ...
```

The "feature-weighted" twist means the coefficients aren't constant — they depend on context:

```
final_score = (w1 × f1 + w2 × f2) × algo1_score
            + (w3 × f1 + w4 × f2) × algo2_score
```

This is still a linear model (linear in parameters), so ordinary linear regression finds the weights efficiently.

---

## Strengths and Weaknesses

**Strengths:**
- Combines the best of multiple algorithms
- Context-aware weights (adapts to user history richness)
- Linear regression training is fast and stable
- More robust than any single algorithm alone

**Weaknesses:**
- Depends on the quality of the base algorithms
- Feature engineering (choosing feature functions) requires domain knowledge
- Adds latency — must call multiple algorithms per request
- Re-training required when base algorithms are retrained

---

## Evaluate

```bash
python evaluator/evaluation_runner.py -fwls
```

The evaluator varies the training sample size and reports how much data is needed for FWLS to outperform the base algorithms.

---

## Next

Once you have recommendations from multiple algorithms, you need a way to measure which is actually better. See `10_evaluation.md` for the evaluation framework.
