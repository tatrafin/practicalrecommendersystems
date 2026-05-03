# 02 — Getting Sample Data

MovieGEEK uses the **MovieTweetings** dataset — a collection of movie ratings extracted from Twitter. It is freely available and regularly updated on GitHub.

---

## Dataset Overview

| File | Contents | Format |
|------|----------|--------|
| `movies.dat` | Movie IDs, titles, genres | `id::title (year)::genre|genre` |
| `ratings.dat` | User ratings (1–10) | `user_id::movie_id::rating::timestamp` |

The dataset contains ratings collected from tweets like:
> *"I rated Inception 9/10 #IMDb"*

Source repository: [github.com/sidooms/MovieTweetings](https://github.com/sidooms/MovieTweetings)

---

## Step 1 — Get a TheMovieDB API Key

The app loads movie posters from [themoviedb.org](https://www.themoviedb.org). You need a free API key.

1. Register at `https://www.themoviedb.org/signup`
2. Go to **Settings → API** and request a Developer key
3. Create a file named `.prs` in the project root with this content:

```json
{"themoviedb_apikey": "YOUR_API_KEY_HERE"}
```

> Without this key the app still works, but movie poster images will be missing.

---

## Step 2 — Set Up the Database

```bash
python manage.py migrate --run-syncdb
```

This creates all the database tables (SQLite by default, stored as `db.sqlite3`).

---

## Step 3 — Populate Movies

```bash
python populate_moviegeek.py
```

What it does:
- Downloads `movies.dat` from the MovieTweetings GitHub repo
- Parses each line: extracts movie ID, title, year, and genres
- Saves `Movie` and `Genre` records to the database
- Skips movies already present (safe to re-run)

Expected output: several thousand movies loaded.

---

## Step 4 — Populate Ratings

```bash
python populate_ratings.py
```

What it does:
- Downloads `ratings.dat` from the MovieTweetings GitHub repo
- Each line becomes a `Rating` record with `user_id`, `movie_id`, `rating` (1–10), and `timestamp`
- Only loads ratings for movies already in the database

Expected output: tens of thousands of ratings loaded.

---

## Step 5 — Populate Interaction Logs

```bash
python populate_logs.py
```

What it does:
- Generates **synthetic** user interaction events (views, purchases)
- Creates `Log` records used by implicit feedback algorithms (BPR)
- Derives events from existing ratings — a highly-rated movie becomes a "buy" event, a viewed-but-not-rated movie becomes a "view" event

> These logs are artificial but realistic enough for learning and evaluation.

---

## Step 6 — Populate Movie Descriptions (for Content-Based)

```bash
python populate_sample_of_descriptions.py
```

What it does:
- Loads text descriptions for a subset of movies
- Stored in the `MovieDescriptions` table
- Required before training the LDA topic model (`builder/lda_model_calculator.py`)

---

## Full Setup Sequence

```bash
# 1. Migrations
python manage.py migrate --run-syncdb

# 2. Data
python populate_moviegeek.py
python populate_ratings.py
python populate_logs.py
python populate_sample_of_descriptions.py

# 3. Run
python manage.py runserver 127.0.0.1:8000
```

---

## PostgreSQL (Optional)

For larger datasets or production use, switch to PostgreSQL by editing `prs_project/settings.py`:

```python
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql_psycopg2',
        'NAME': 'prs_db',
        'USER': 'your_user',
        'PASSWORD': 'your_password',
        'HOST': 'localhost',
        'PORT': '5432',
    }
}
```

Then re-run `migrate` and the populate scripts.

---

## Docker Alternative

```bash
docker-compose build web
./db-migrate.sh     # creates DB and runs all populate scripts
docker-compose up web
```

---

## What You Have After Setup

| Table | Records |
|-------|---------|
| `moviegeeks_movie` | ~10,000+ movies |
| `moviegeeks_genre` | ~20 genres |
| `analytics_rating` | ~100,000+ ratings |
| `collector_log` | Synthetic interaction events |
| `recommender_moviedescriptions` | Text descriptions (subset) |

You are now ready to train models — see `05_collaborative_filtering.md` onward for building each algorithm's model.
