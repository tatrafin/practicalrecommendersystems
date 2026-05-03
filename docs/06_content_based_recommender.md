# 06 — Content-Based Recommender (LDA)

## The Core Idea

Content-based filtering recommends items **similar in content** to what a user has liked before. Instead of looking at other users' behavior, it analyzes the items themselves — in this case, movie descriptions.

The technique used here is **Latent Dirichlet Allocation (LDA)**, a topic modeling algorithm. LDA reads movie descriptions and discovers hidden topics (e.g., "action/adventure", "romance", "sci-fi thriller"). Each movie is then represented as a mixture of these topics, and similarity is measured between those topic mixtures.

**Files:**
- Algorithm: `recs/content_based_recommender.py` — `ContentBasedRecs`
- Model builder: `builder/lda_model_calculator.py` — `LdaModel`

---

## Phase 1 — Building the LDA Model (Offline)

### Step 1 — Load Movie Descriptions

```python
descriptions = MovieDescriptions.objects.all()
```

Each record has a `description` text field and a `genres` field. The builder combines these into a single text document per movie.

### Step 2 — Text Preprocessing

```python
from stop_words import get_stop_words

stop_words = get_stop_words('english')

def tokenize(text):
    tokens = text.lower().split()
    return [t for t in tokens if t not in stop_words]
```

- Convert to lowercase
- Split into words (tokens)
- Remove common stop words ("the", "a", "is", etc.)

### Step 3 — Build a Dictionary and Corpus

Gensim requires two data structures:

- **Dictionary** — maps each unique word to an integer ID
- **Corpus** — each movie's description as a bag-of-words: list of `(word_id, count)` pairs

```python
from gensim import corpora
dictionary = corpora.Dictionary(tokenized_docs)
corpus = [dictionary.doc2bow(doc) for doc in tokenized_docs]
```

### Step 4 — Train the LDA Model

```python
from gensim.models import LdaModel

lda = LdaModel(
    corpus=corpus,
    id2word=dictionary,
    num_topics=10,
    passes=10
)
```

- `num_topics=10` — discover 10 hidden topics across all movie descriptions
- `passes=10` — iterate over the corpus 10 times for better convergence

After training, each movie can be represented as a vector of 10 numbers — one probability per topic. For example:
```
Movie: Inception
Topics: [sci-fi: 0.4, thriller: 0.3, drama: 0.2, action: 0.1, ...]
```

### Step 5 — Compute Similarities and Store

For every pair of movies, compute cosine similarity between their topic vectors and store the result in `LdaSimilarity`:

```python
sim = cosine_similarity(topic_vector_A, topic_vector_B)
LdaSimilarity.objects.create(source=movie_A, target=movie_B, sim=sim)
```

### Step 6 — Save LDA Visualization

The builder also exports topic data as JSON for the interactive LDA visualization at `/analytics/lda/`:

```python
import pyLDAvis
vis_data = pyLDAvis.gensim.prepare(lda, corpus, dictionary)
pyLDAvis.save_json(vis_data, 'static/js/lda.json')
```

### Run the builder:

```bash
python builder/lda_model_calculator.py
```

---

## Phase 2 — Serving Recommendations (Online)

**Class:** `ContentBasedRecs`

The recommendation logic mirrors the neighborhood-based CF approach, but uses `LdaSimilarity` instead of `Similarity`:

```python
def recommend_items_by_ratings(self, user_id, num=6):
    user_ratings = Rating.objects.filter(user_id=user_id)

    # For each movie the user rated:
    #   find its most similar movies (by LDA similarity)
    #   weight by similarity × user_rating_deviation
    # Aggregate scores and return top-N
```

### Seeded Recommendations

A unique feature of content-based: **recommend similar items to a specific seed movie**, without needing a user profile:

```
GET /recommender/content_similar/{movie_id}/
```

```python
def seeded_rec(self, movie_id, num=6):
    similar = LdaSimilarity.objects.filter(
        source=movie_id
    ).order_by('-sim')[:num]
    return [s.target for s in similar]
```

This works even for brand new users — you just need a seed item.

---

## API Endpoints

```
GET /recommender/cb/{user_id}/          # Personalized content-based recs
GET /recommender/content_similar/{id}/  # Items similar to a given movie
```

---

## Understanding LDA Topics

LDA topics are not labeled — the algorithm discovers them automatically. You interpret them by looking at the top words per topic:

| Topic | Top words | Likely meaning |
|-------|-----------|----------------|
| 0 | war, soldier, battle, army | War films |
| 1 | love, romance, couple, heart | Romantic films |
| 2 | space, alien, planet, future | Sci-fi |
| ... | ... | ... |

The `/analytics/lda/` page renders the pyLDAvis interactive visualization where you can explore this.

---

## Strengths and Weaknesses

**Strengths:**
- No cold start for **items** — works for new movies if a description exists
- No need for other users' data
- Explainable — "recommended because it covers similar topics"
- Seeded recommendations work with zero user history

**Weaknesses:**
- Cold start for **users** — still needs some rated items to build a profile
- Quality depends on description quality — poor text = poor topics
- Over-specialization — tends to recommend very similar content, limiting discovery
- LDA is probabilistic; topics may not always be coherent

---

## Evaluate

```bash
python evaluator/evaluation_runner.py -cb
```

The evaluator varies the neighborhood size (K) and reports MAP and Recall@K.

---

## Next

Neither CF nor CB captures the full picture individually. Matrix factorization (SVD) learns a compressed representation of both users and items simultaneously. See `07_matrix_factorization.md`.
