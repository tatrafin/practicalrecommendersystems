# 03 — Data Models

Understanding the database schema is essential before diving into the algorithms. Each Django app owns a portion of the schema.

---

## Entity Relationship Overview

```
Movie ──< Genre (M2M)
Movie ──< Rating >── User
Movie ──< Log >── User
Movie ──< MovieDescriptions
Movie ──< Similarity >── Movie   (item-item CF similarity)
Movie ──< LdaSimilarity >── Movie (content-based similarity)
Movie ──< SeededRecs >── Movie   (association rules)
User  ──< Cluster
```

---

## moviegeeks App

### Movie (`moviegeeks/models.py`)

The central entity. Every algorithm references movies by `movie_id`.

```python
class Movie(models.Model):
    movie_id = models.CharField(max_length=15, primary_key=True)
    title    = models.CharField(max_length=255)
    year     = models.IntegerField(null=True)
    genres   = models.ManyToManyField(Genre)
```

- `movie_id` is the IMDb ID string (e.g. `"0133093"` for The Matrix)
- `genres` is a many-to-many relation — one movie can have multiple genres

### Genre

```python
class Genre(models.Model):
    name = models.CharField(max_length=64)
```

---

## analytics App

### Rating (`analytics/models.py`)

Explicit user ratings — the primary signal for collaborative filtering.

```python
class Rating(models.Model):
    user_id           = models.IntegerField()
    movie_id          = models.CharField(max_length=15)
    rating            = models.DecimalField(max_digits=5, decimal_places=2)
    rating_timestamp  = models.BigIntegerField(null=True)
    type              = models.CharField(max_length=1)  # 'E' explicit, 'I' implicit
```

- Ratings are on a 1–10 scale (from MovieTweetings)
- `type` distinguishes explicit ratings from implicit ones derived from logs

### Cluster (`analytics/models.py`)

Groups users by rating behavior (K-Means output).

```python
class Cluster(models.Model):
    cluster_id = models.IntegerField()
    user_id    = models.IntegerField()
```

---

## collector App

### Log (`collector/models.py`)

Captures implicit user behavior — every page view, purchase, or interaction.

```python
class Log(models.Model):
    created    = models.DateTimeField(auto_now_add=True)
    user_id    = models.IntegerField()
    content_id = models.CharField(max_length=15)  # movie_id
    event      = models.CharField(max_length=64)  # 'view', 'buy', etc.
    session_id = models.CharField(max_length=64)
```

- Used by BPR (implicit feedback algorithm)
- Events are logged by JavaScript on the front-end via POST to `collector/views.py`

---

## recommender App

### Similarity (`recommender/models.py`)

Pre-computed item-to-item similarity scores used by neighborhood-based CF.

```python
class Similarity(models.Model):
    source  = models.CharField(max_length=15)   # movie_id
    target  = models.CharField(max_length=15)   # movie_id
    created = models.DateTimeField(auto_now_add=True)
    sim     = models.DecimalField(max_digits=10, decimal_places=9)
```

- Populated by `builder/item_similarity_calculator.py`
- Cosine similarity between items, based on normalized user rating vectors
- Only pairs with similarity > 0.2 and at least 15 common raters are stored

### LdaSimilarity (`recommender/models.py`)

Similarity between movies based on text topic distributions (LDA).

```python
class LdaSimilarity(models.Model):
    source  = models.CharField(max_length=15)
    target  = models.CharField(max_length=15)
    created = models.DateTimeField(auto_now_add=True)
    sim     = models.DecimalField(max_digits=10, decimal_places=9)
```

- Populated by `builder/lda_model_calculator.py`
- Cosine similarity between LDA topic vectors of movie descriptions

### SeededRecs (`recommender/models.py`)

Association rules between item pairs.

```python
class SeededRecs(models.Model):
    source     = models.CharField(max_length=15)
    target     = models.CharField(max_length=15)
    created    = models.DateTimeField(auto_now_add=True)
    support    = models.DecimalField(max_digits=10, decimal_places=9)
    confidence = models.DecimalField(max_digits=10, decimal_places=9)
    score      = models.DecimalField(max_digits=10, decimal_places=9)
```

- Support = fraction of users who rated both source and target
- Confidence = fraction of source raters who also rated target

### MovieDescriptions (`recommender/models.py`)

Raw text for content-based filtering.

```python
class MovieDescriptions(models.Model):
    movie_id    = models.CharField(max_length=15, primary_key=True)
    title       = models.CharField(max_length=255)
    description = models.TextField()
    genres      = models.CharField(max_length=255)
```

- Descriptions are used as input to the LDA topic model
- Populated by `populate_sample_of_descriptions.py`

### Recs (`recommender/models.py`)

Pre-computed recommendations (optional caching layer).

```python
class Recs(models.Model):
    user_id  = models.IntegerField()
    movie_id = models.CharField(max_length=15)
    rating   = models.DecimalField(max_digits=10, decimal_places=9)
    type     = models.CharField(max_length=20)
```

---

## How Algorithms Use the Schema

| Algorithm | Reads from | Writes to |
|-----------|-----------|-----------|
| Popularity | `Rating` | — |
| Neighborhood CF | `Rating`, `Similarity` | — |
| Content-Based | `Rating`, `LdaSimilarity` | — |
| Funk SVD | `Rating` (via files) | JSON factor files |
| BPR | `Log` (via files) | JSON factor files |
| FWLS | `Rating`, `Similarity`, `LdaSimilarity` | `fwls_parameters.data` |
| Item Similarity Builder | `Rating` | `Similarity` |
| LDA Builder | `MovieDescriptions` | `LdaSimilarity` |
| Association Rules | `Rating` | `SeededRecs` |
| User Clustering | `Rating` | `Cluster` |

---

## Key Observations

1. **User IDs are integers** but there is no `User` model — users are anonymous, identified only by a session-generated integer stored in a cookie.
2. **movie_id is a string** (IMDb ID), not an auto-increment integer. This means joins are string comparisons.
3. **Similarity tables are asymmetric** — `(A→B)` and `(B→A)` may both be stored.
4. **Matrix factorization models** (Funk SVD, BPR) are saved as JSON files on disk, not in the database.
