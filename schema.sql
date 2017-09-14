-- 1 up
CREATE TABLE IF NOT EXISTS tweets (
        tweet_id SERIAL PRIMARY KEY,
        user_id INTEGER REFERENCES users,
        tweet TEXT,
        timestamp TIMESTAMP NOT NULL DEFAULT now(),
        added     TIMESTAMP NOT NULL DEFAULT now(),
        UNIQUE ( user_id,tweet,timestamp )
);

CREATE TABLE IF NOT EXISTS users (
        user_id SERIAL PRIMARY KEY,
        nick TEXT,
        url TEXT UNIQUE,
        timestamp TIMESTAMP NOT NULL DEFAULT now(),
	last_modified TEXT,
	active BOOLEAN DEFAULT TRUE,
	last_error TEXT,
	is_bot BOOLEAN DEFAULT FALSE,
);

CREATE TABLE IF NOT EXISTS tweets_tags (
	tag_id   INTEGER REFERENCES tags,
	tweet_id INTEGER REFERENCES tweets,
	PRIMARY KEY ( tag_id, tweet_id )
);

CREATE TABLE IF NOT EXISTS tags (
	tag_id SERIAL PRIMARY KEY,
	name TEXT UNIQUE NOT NULL
);

CREATE TABLE IF NOT EXISTS mentions (
	user_id  INTEGER NOT NULL REFERENCES users,
	tweet_id INTEGER NOT NULL REFERENCES tweets,
	PRIMARY KEY ( user_id, tweet_id)
);
