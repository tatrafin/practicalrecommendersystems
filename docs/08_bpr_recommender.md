# 08 — Bayesian Personalized Ranking (BPR)

## The Core Idea

Funk SVD tries to predict exact rating values. BPR takes a fundamentally different approach: it doesn't care about the exact score — it only cares that **items a user interacted with are ranked higher than items they didn't**.

This makes BPR particularly suited for **implicit feedback** — data like clicks, views, and purchases — where you don't have a 1–10 scale, just a signal that the user showed interest.

**Files:**
- Algorithm: `recs/bpr_recommender.py` — `BPRRecs`
- Model builder: `builder/bpr_calculator.py` — `BayesianPersonalizationRanking`

---

## Implicit Feedback vs. Explicit Ratings

| Type | Example | What it tells us |
|------|---------|-----------------|
| Explicit | User rated movie 8/10 | Direct preference signal |
| Implicit | User viewed or purchased movie | Interest, but no magnitude |

With implicit feedback, you observe **positive interactions** but no negatives. A user didn't watch a movie — did they dislike it, or just never encounter it? BPR handles this uncertainty via **pairwise ranking**.

In MovieGEEK, implicit data comes from the `collector_log` table (events logged by `populate_logs.py`).

---

## The Pairwise Learning Approach

Instead of asking "what rating will the user give item i?", BPR asks:

> For user u, does user u prefer item i over item j?

**Assumption:** If user u interacted with item i but not item j, then u prefers i over j.

For each training sample, BPR draws:
- A **positive item** i — something the user has interacted with
- A **negative item** j — a random item the user has not interacted with

The model is trained to rank i above j for user u.

---

## The Model

Like Funk SVD, BPR represents users and items as latent vectors in a k-dimensional space:

- **P[u]** — user u's latent vector (length k)
- **Q[i]** — item i's latent vector (length k)

The predicted score for a user-item pair is simply the dot product:

```
score(u, i) = P[u] · Q[i]
```

The preference of u for i over j is:

```
x_uij = score(u, i) - score(u, j) = P[u] · Q[i] - P[u] · Q[j]
```

The model wants `x_uij` to be positive (i ranked above j).

---

## Training

### Objective: Maximize the Bayesian Posterior

BPR maximizes the probability that observed pairwise preferences are correct:

```
BPR-OPT = Σ ln σ(x_uij) - λ × |Θ|²
```

Where:
- `σ` is the sigmoid function (converts score difference to probability)
- `Θ` = {P, Q} are all model parameters
- `λ` is regularization

### SGD Update per Sample

```python
for each sampled (user, positive_item, negative_item):
    x_uij = dot(P[u], Q[i]) - dot(P[u], Q[j])
    sigmoid_x = sigmoid(-x_uij)   # gradient signal

    # Update user vector
    P[u] += lr × (sigmoid_x × (Q[i] - Q[j]) - reg × P[u])

    # Update positive item vector
    Q[i] += lr × (sigmoid_x × P[u] - reg × Q[i])

    # Update negative item vector
    Q[j] += lr × (-sigmoid_x × P[u] - reg × Q[j])
```

**Hyperparameters:**
```python
k             = 5      # number of latent factors (sweep 5–50 in evaluation)
learning_rate = 0.05   # step size
regularization = 0.01
epochs        = 10
```

### The Training Loop

```python
for epoch in range(epochs):
    for user in users:
        # Sample a positive item (one the user interacted with)
        pos_item = random.choice(user_interactions[user])

        # Sample a negative item (one they haven't seen)
        neg_item = random_unrated_item(user)

        # Update model
        update(user, pos_item, neg_item)
```

This is **bootstrap sampling** — each epoch samples a different subset of triples, making training stochastic and fast.

---

## Saving and Loading

Like Funk SVD, model parameters are saved to disk:

```
bpr_user_factors.json    # {user_id: [f1, ..., fk]}
bpr_item_factors.json    # {movie_id: [f1, ..., fk]}
```

---

## Serving Recommendations

```python
def predict_score(self, user_id, movie_id):
    return dot(self.user_factors[user_id], self.item_factors[movie_id])

def recommend_items(self, user_id, num=6):
    already_seen = get_user_interactions(user_id)
    scores = {
        movie_id: self.predict_score(user_id, movie_id)
        for movie_id in all_movies
        if movie_id not in already_seen
    }
    return sorted(scores, key=scores.get, reverse=True)[:num]
```

No bias terms — unlike Funk SVD, BPR doesn't try to predict absolute scores, so biases aren't needed.

---

## Run Training

```bash
python builder/bpr_calculator.py
```

---

## API Endpoint

```
GET /recommender/bpr/{user_id}/
```

---

## BPR vs. Funk SVD

| | Funk SVD | BPR |
|--|----------|-----|
| Input | Explicit ratings | Implicit interactions |
| Goal | Minimize rating error | Maximize ranking accuracy |
| Loss | Mean squared error | Pairwise ranking loss |
| Output | Predicted score (1–10) | Ranking score (relative) |
| Bias terms | Yes | No |
| Use case | "What rating would this user give?" | "What should I show first?" |

---

## Strengths and Weaknesses

**Strengths:**
- Designed for implicit feedback (the dominant signal in real systems)
- Optimizes ranking directly, which is what matters for recommendations
- Simple and fast to train with bootstrap sampling

**Weaknesses:**
- Cold start — new users/items have no latent vectors
- Negative sampling is heuristic — an uninteracted item might just be undiscovered
- No explicit rating prediction — can't tell you "the user will rate this 8/10"

---

## Evaluate

```bash
python evaluator/evaluation_runner.py -bpr
```

BPR is evaluated with Recall@K rather than MAE, because it's a ranking method. The evaluator sweeps over values of k.

---

## Next

We now have five algorithms: popularity, CF, content-based, Funk SVD, and BPR. Each has strengths the others lack. The natural next step is to combine them. See `09_hybrid_recommender.md`.
