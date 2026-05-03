BEGIN TRANSACTION;
CREATE TABLE IF NOT EXISTS analytics_cluster (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    cluster_id INTEGER NOT NULL,
    user_id INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS analytics_rating (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id VARCHAR(16) NOT NULL,
    movie_id VARCHAR(16) NOT NULL,
    rating DECIMAL(4, 2) NOT NULL,
    rating_timestamp DATETIME NOT NULL,
    type VARCHAR(8) NOT NULL DEFAULT 'explicit'
);
CREATE TABLE IF NOT EXISTS "auth_group" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "name" varchar(150) NOT NULL UNIQUE);
CREATE TABLE IF NOT EXISTS "auth_group_permissions" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "group_id" integer NOT NULL REFERENCES "auth_group" ("id") DEFERRABLE INITIALLY DEFERRED, "permission_id" integer NOT NULL REFERENCES "auth_permission" ("id") DEFERRABLE INITIALLY DEFERRED);
CREATE TABLE IF NOT EXISTS "auth_permission" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "content_type_id" integer NOT NULL REFERENCES "django_content_type" ("id") DEFERRABLE INITIALLY DEFERRED, "codename" varchar(100) NOT NULL, "name" varchar(255) NOT NULL);
CREATE TABLE IF NOT EXISTS "auth_user" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "password" varchar(128) NOT NULL, "last_login" datetime NULL, "is_superuser" bool NOT NULL, "username" varchar(150) NOT NULL UNIQUE, "last_name" varchar(150) NOT NULL, "email" varchar(254) NOT NULL, "is_staff" bool NOT NULL, "is_active" bool NOT NULL, "date_joined" datetime NOT NULL, "first_name" varchar(150) NOT NULL);
CREATE TABLE IF NOT EXISTS "auth_user_groups" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "user_id" integer NOT NULL REFERENCES "auth_user" ("id") DEFERRABLE INITIALLY DEFERRED, "group_id" integer NOT NULL REFERENCES "auth_group" ("id") DEFERRABLE INITIALLY DEFERRED);
CREATE TABLE IF NOT EXISTS "auth_user_user_permissions" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "user_id" integer NOT NULL REFERENCES "auth_user" ("id") DEFERRABLE INITIALLY DEFERRED, "permission_id" integer NOT NULL REFERENCES "auth_permission" ("id") DEFERRABLE INITIALLY DEFERRED);
CREATE TABLE IF NOT EXISTS collector_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created DATETIME NOT NULL,
    user_id VARCHAR(16) NOT NULL,
    content_id VARCHAR(16) NOT NULL,
    event VARCHAR(200) NOT NULL,
    session_id VARCHAR(128) NOT NULL
);
CREATE TABLE IF NOT EXISTS "django_admin_log" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "object_id" text NULL, "object_repr" varchar(200) NOT NULL, "action_flag" smallint unsigned NOT NULL CHECK ("action_flag" >= 0), "change_message" text NOT NULL, "content_type_id" integer NULL REFERENCES "django_content_type" ("id") DEFERRABLE INITIALLY DEFERRED, "user_id" integer NOT NULL REFERENCES "auth_user" ("id") DEFERRABLE INITIALLY DEFERRED, "action_time" datetime NOT NULL);
CREATE TABLE IF NOT EXISTS "django_content_type" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "app_label" varchar(100) NOT NULL, "model" varchar(100) NOT NULL);
CREATE TABLE IF NOT EXISTS "django_migrations" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "app" varchar(255) NOT NULL, "name" varchar(255) NOT NULL, "applied" datetime NOT NULL);
CREATE TABLE IF NOT EXISTS "django_session" ("session_key" varchar(40) NOT NULL PRIMARY KEY, "session_data" text NOT NULL, "expire_date" datetime NOT NULL);
CREATE TABLE IF NOT EXISTS lda_similarity (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created DATE NOT NULL,
    source VARCHAR(16) NOT NULL,
    target VARCHAR(16) NOT NULL,
    similarity DECIMAL(8, 7) NOT NULL
);
CREATE TABLE IF NOT EXISTS movie_description (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    movie_id VARCHAR(16) NOT NULL,
    imdb_id VARCHAR(16) NOT NULL,
    title VARCHAR(512) NOT NULL,
    description VARCHAR(1024) NOT NULL,
    genres VARCHAR(512) NOT NULL DEFAULT '',
    lda_vector VARCHAR(56) NULL,
    sim_list VARCHAR(512) NOT NULL DEFAULT ''
);
CREATE TABLE IF NOT EXISTS movie_genre (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    movie_id VARCHAR(16) NOT NULL REFERENCES moviegeeks_movie (movie_id),
    genre_id INTEGER NOT NULL REFERENCES moviegeeks_genre (id)
);
CREATE TABLE IF NOT EXISTS moviegeeks_genre (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name VARCHAR(64) NOT NULL
);
CREATE TABLE IF NOT EXISTS moviegeeks_movie (
    movie_id VARCHAR(16) PRIMARY KEY,
    title VARCHAR(512) NOT NULL,
    year INTEGER NULL
);
CREATE TABLE IF NOT EXISTS recs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    "user" VARCHAR(16) NOT NULL,
    item VARCHAR(16) NOT NULL,
    rating REAL NOT NULL,
    type VARCHAR(16) NOT NULL
);
CREATE TABLE IF NOT EXISTS seeded_recs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created DATETIME NOT NULL,
    source VARCHAR(16) NOT NULL,
    target VARCHAR(16) NOT NULL,
    support DECIMAL(10, 8) NOT NULL,
    confidence DECIMAL(10, 8) NOT NULL,
    type VARCHAR(8) NOT NULL
);
CREATE TABLE IF NOT EXISTS similarity (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created DATE NOT NULL,
    source VARCHAR(16) NOT NULL,
    target VARCHAR(16) NOT NULL,
    similarity DECIMAL(8, 7) NOT NULL
);
CREATE INDEX "auth_group_permissions_group_id_b120cbf9" ON "auth_group_permissions" ("group_id");
CREATE UNIQUE INDEX "auth_group_permissions_group_id_permission_id_0cd325b0_uniq" ON "auth_group_permissions" ("group_id", "permission_id");
CREATE INDEX "auth_group_permissions_permission_id_84c5c92e" ON "auth_group_permissions" ("permission_id");
CREATE INDEX "auth_permission_content_type_id_2f476e4b" ON "auth_permission" ("content_type_id");
CREATE UNIQUE INDEX "auth_permission_content_type_id_codename_01ab375a_uniq" ON "auth_permission" ("content_type_id", "codename");
CREATE INDEX "auth_user_groups_group_id_97559544" ON "auth_user_groups" ("group_id");
CREATE INDEX "auth_user_groups_user_id_6a12ed8b" ON "auth_user_groups" ("user_id");
CREATE UNIQUE INDEX "auth_user_groups_user_id_group_id_94350c0c_uniq" ON "auth_user_groups" ("user_id", "group_id");
CREATE INDEX "auth_user_user_permissions_permission_id_1fbb5f2c" ON "auth_user_user_permissions" ("permission_id");
CREATE INDEX "auth_user_user_permissions_user_id_a95ead1b" ON "auth_user_user_permissions" ("user_id");
CREATE UNIQUE INDEX "auth_user_user_permissions_user_id_permission_id_14a6b632_uniq" ON "auth_user_user_permissions" ("user_id", "permission_id");
CREATE INDEX "django_admin_log_content_type_id_c4bce8eb" ON "django_admin_log" ("content_type_id");
CREATE INDEX "django_admin_log_user_id_c564eba6" ON "django_admin_log" ("user_id");
CREATE UNIQUE INDEX "django_content_type_app_label_model_76bd3d3b_uniq" ON "django_content_type" ("app_label", "model");
CREATE INDEX "django_session_expire_date_a5c62663" ON "django_session" ("expire_date");
CREATE INDEX lda_similarity_source_idx ON lda_similarity (source);
CREATE INDEX similarity_source_idx ON similarity (source);
COMMIT;
