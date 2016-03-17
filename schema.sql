CREATE TABLE tweets (
        tweet_id INTEGER PRIMARY KEY,
        user INTEGER NOT NULL,
        tweet TEXT,
        timestamp INTEGER NOT NULL DEFAULT ( strftime('%s','now') ),
        added     INTEGER NOT NULL DEFAULT ( strftime('%s','now') ),
        FOREIGN KEY(user) REFERENCES users(user_id) ON DELETE CASCADE,
        CONSTRAINT tweet_user_timestamp UNIQUE ( user,tweet,timestamp )
);
CREATE TABLE users (
        user_id INTEGER PRIMARY KEY,
        nick TEXT,
        url TEXT UNIQUE,
        timestamp INTEGER NOT NULL DEFAULT ( strftime('%s','now') ),
	last_modified TEXT,
	active INTEGER DEFAULT 1,
	last_error TEXT
);

