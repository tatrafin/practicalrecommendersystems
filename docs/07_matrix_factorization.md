# 07 — Matrix Factorization (Funk SVD)

## The Core Idea

Matrix factorization tackles the rating prediction problem differently from neighborhood methods. Instead of comparing items or users directly, it **decomposes the user-item rating matrix into two smaller matrices** — one representing users and one representing items — in a shared latent space.

The name "Funk SVD" comes from Simon Funk, who popularized this approach during the Netflix Prize competition. It's not true SVD (which can't handle missing values), but uses the same intuition: represent each user and item as a short vector of latent features, where the dot product of a user vector and an item vector predicts the rating.

**Files:**
- Algorithm: `recs/funksvd_recommender.py` — `FunkSVDRecs`
- Model builder: `builder/matrix_factorization_calculator.py` — `MatrixFactorization`

---

## The Math

### Rating Matrix

Imagine a matrix R where rows are users and columns are movies. Most cells are empty (not rated):

```
         Movie1  Movie2  Movie3  Movie4
User1  [  8       ?       6       ?   ]
User2  [  ?       9       ?       7   ]
User3  [  5       ?       ?       8   ]
```

### Factorization

The goal is to find two matrices:
- **P** (users × k): each row is a user's latent feature vector
- **Q** (items × k): each row is an item's latent feature vector

Such that:  `R ≈ P × Qᵀ`

For a single user-item pair:  `predicted_rating(u, i) = P[u] · Q[i]`

The number of latent factors `k` is a hyperparameter (typically 20–40). Each factor captures some abstract dimension — maybe "action vs. romance" or "mainstream vs. art-house" — but these dimensions are never labeled.

### Adding Bias Terms

Raw dot product isn't enough. Some users rate higher on average (generous raters), some movies are rated higher on average (blockbusters). The model adds bias terms:

```
predicted_rating(u, i) = global_mean
                        + user_bias[u]
                        + item_bias[i]
                        + P[u] · Q[i]
```

---

## Training with Stochastic Gradient Descent (SGD)

The model learns P and Q by minimizing prediction error over all known ratings.

### Loss Function

```
Loss = Σ (rating(u,i) - predicted(u,i))² + λ × (|P[u]|² + |Q[i]|²)
```

- The first term is the squared error on known ratings
- The second term (regularization λ) penalizes large factor values to prevent overfitting

### Update Rules (per rating)

For each observed rating `r(u, i)`:

```python
error = r(u, i) - predicted(u, i)

# Update biases
user_bias[u] += learn_rate × (error - reg × user_bias[u])
item_bias[i] += learn_rate × (error - reg × item_bias[i])

# Update latent factors
for f in range(k):
    p_uf = P[u][f]
    q_if = Q[i][f]
    P[u][f] += learn_rate × (error × q_if - reg × p_uf)
    Q[i][f] += learn_rate × (error × p_uf - reg × q_if)
```

**Hyperparameters in this project:**
```python
k            = 20      # number of latent factors
learn_rate   = 0.002   # step size for gradient descent
reg          = 0.002   # regularization strength
epochs       = 10      # passes over all ratings
```

### Training Loop

```python
for epoch in range(epochs):
    for user_id, movie_id, rating in all_ratings:
        predicted = predict(user_id, movie_id)
        error = rating - predicted
        update_biases(user_id, movie_id, error)
        update_factors(user_id, movie_id, error)
```

---

## Saving and Loading the Model

The trained matrices are saved as JSON files on disk:

```
user_factors.json    # P matrix: {user_id: [f1, f2, ..., fk]}
item_factors.json    # Q matrix: {movie_id: [f1, f2, ..., fk]}
user_bias.data       # {user_id: bias}
item_bias.data       # {movie_id: bias}
```

The recommender class loads these at startup:

```python
class FunkSVDRecs:
    def __init__(self):
        self.user_factors = load_json('user_factors.json')
        self.item_factors = load_json('item_factors.json')
        self.user_bias = load_json('user_bias.data')
        self.item_bias = load_json('item_bias.data')
        self.global_mean = compute_global_mean()
```

---

## Serving Recommendations

```python
def predict_score(self, user_id, movie_id):
    pu = self.user_factors[user_id]
    qi = self.item_factors[movie_id]
    return (self.global_mean
            + self.user_bias[user_id]
            + self.item_bias[movie_id]
            + dot(pu, qi))

def recommend_items(self, user_id, num=6):
    already_rated = get_rated_movies(user_id)
    scores = {
        movie_id: self.predict_score(user_id, movie_id)
        for movie_id in all_movies
        if movie_id not in already_rated
    }
    return sorted(scores, key=scores.get, reverse=True)[:num]
```

---

## Run Training

```bash
python builder/matrix_factorization_calculator.py
```

Training can take several minutes depending on dataset size. Progress is shown with `tqdm`.

---

## API Endpoint

```
GET /recommender/funksvd/{user_id}/
```

---

## Strengths and Weaknesses

**Strengths:**
- Captures global patterns across all users and items simultaneously
- Handles sparsity well — learns from partial data
- Bias terms improve accuracy significantly
- Latent factors can capture subtle taste dimensions

**Weaknesses:**
- Cold start — new users/items with no ratings get no latent vector
- Opaque — you can't explain why a recommendation was made
- Requires re-training when new ratings come in
- Hyperparameter tuning needed (k, learning rate, regularization)

---

## Evaluate

```bash
python evaluator/evaluation_runner.py -funk
```

The evaluator sweeps over different values of `k` (number of factors) and reports MAP and Recall@K. More factors don't always mean better results due to overfitting.

---

## Next

Funk SVD optimizes for rating accuracy (predicting the exact score). But sometimes what matters more is **ranking** — especially when feedback is implicit (clicks, views, purchases) rather than explicit ratings. BPR addresses this. See `08_bpr_recommender.md`.
