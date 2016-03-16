CREATE TABLE tweets (
        id INTEGER PRIMARY KEY,
        user INTEGER NOT NULL,
        tweet TEXT,
        timestamp NOT NULL DEFAULT ( strftime('%s','now') ),
        FOREIGN KEY(user) REFERENCES users(id),
        CONSTRAINT tweet_user_timestamp UNIQUE ( user,tweet,timestamp ) ON CONFLICT IGNORE
);
CREATE TABLE users (
        id INTEGER PRIMARY KEY,
        nick TEXT,
        url TEXT UNIQUE,
        timestamp NOT NULL DEFAULT ( strftime('%s','now') ),
	last_modified text,
);

