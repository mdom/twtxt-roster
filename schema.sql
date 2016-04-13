CREATE TABLE if not exists tweets (
        tweet_id INTEGER PRIMARY KEY,
        user_id INTEGER NOT NULL,
        tweet TEXT,
        timestamp INTEGER NOT NULL DEFAULT ( strftime('%s','now') ),
        added     INTEGER NOT NULL DEFAULT ( strftime('%s','now') ),
        FOREIGN KEY(user_id) REFERENCES users(user_id) ON DELETE CASCADE,
        CONSTRAINT tweet_user_timestamp UNIQUE ( user_id,tweet,timestamp )
);

CREATE TABLE if not exists users (
        user_id INTEGER PRIMARY KEY,
        nick TEXT,
        url TEXT UNIQUE,
        timestamp INTEGER NOT NULL DEFAULT ( strftime('%s','now') ),
	last_modified TEXT,
	active INTEGER DEFAULT 1,
	last_error TEXT,
	is_bot INTEGER DEFAULT 0
);

create table if not exists tweets_tags (
	tag_id   integer references tags,
	tweet_id integer references tweets,
	primary key ( tag_id, tweet_id )
);

create table if not exists tags (
	tag_id integer primary key,
	name text unique not null
);

create table if not exists mentions (
	user_id    integer not null references users,
	tweet_id   integer not null references tweets,
	primary key ( user_id, tweet_id)
);
