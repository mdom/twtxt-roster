package App::TwtxtRoster::Controller::Tweets;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Loader 'data_section';

sub get_tweets {
    my $c         = shift;
    my $query     = $c->param('q') || '%';
    my $show_bots = $c->param('show_bots') || 0;
    $c->stash( template => 'tweets' );

    if ( substr( $query, 0, 1 ) eq '@' ) {
        $c->param( nick => substr( $query, 1 ) );
        return $c->get_mentions;
    }

    if ( substr( $query, 0, 1 ) eq '#' ) {
        $c->param( tag => substr( $query, 1 ) );
        return $c->get_tags;
    }

    my $stmt = data_section( __PACKAGE__, 'select_tweet_like.sql' );
    return $c->respond_to_api( $stmt, "%$query%", $show_bots, $c->offset );
}

sub get_tweets_by_user {
    my $c = shift;
    $c->stash( template => 'tweets' );
    my $stmt = data_section( __PACKAGE__, 'select_user.sql' );
    return $c->respond_to_api( $stmt, $c->param('user'), $c->offset );
}

sub get_mentions {
    my $c         = shift;
    my $url       = $c->param('url');
    my $nick      = $c->param('nick');
    my $show_bots = $c->param('show_bots') || 0;
    return $c->render(
        status => 400,
        text   => '`url` or `nick` must be provided.'
    ) if !$url and !$nick;
    $c->stash( template => 'tweets' );
    my $stmt = data_section( __PACKAGE__, 'select_mentions.sql' );
    return $c->respond_to_api( $stmt, $url, $nick, $show_bots, $c->offset );
}

sub get_tags {
    my $c         = shift;
    my $tag       = $c->param('tag');
    my $show_bots = $c->param('show_bots') || 0;
    return $c->render( status => 400, text => '`tag` must be provided.' )
      if !$tag;
    $c->stash( template => 'tweets' );
    my $stmt = data_section( __PACKAGE__, 'select_tags.sql' );
    return $c->respond_to_api( $stmt, $tag, $show_bots, $c->offset );
}

sub list_tags {
    my $c = shift;
    my $tag = ( $c->param('term') || '' ) . '%';
    return $c->render(
        json =>
          $c->sql->db->query( 'select "#"||name from tags where name like ?',
            $tag )->arrays->flatten
    );
}

sub stream {
    my $c = shift;
    $c->inactivity_timeout(0);
    $c->sql->pubsub->listen(
        'new_tweet' => sub {
            my ( $pubsub, $payload ) = @_;
            $c->send( { text => $payload } );
        }
    );
    $c->on(
        finish => sub {
            my ( $c, $code, $reason ) = @_;
            $c->sql->pubsub->unlisten('new_tweet');
            $c->app->log->debug("WebSocket closed with status $code");
        }
    );
}

1;

__DATA__

@@ select_user.sql

select users.nick, users.url ,strftime('%Y-%m-%dT%H:%M:%SZ',tweets.timestamp,"unixepoch") as time, tweets.tweet
    from tweets join users using ( user_id )
    where url is ?
    order by tweets.timestamp desc limit 20 offset ?

@@ select_tweet_like.sql

select users.nick, users.url ,strftime('%Y-%m-%dT%H:%M:%SZ',tweets.timestamp,"unixepoch") as time, tweets.tweet
    from tweets join users using ( user_id )
    where
          tweet like ?
      and case when ? then 1 else is_bot is 0 end
    order by tweets.timestamp desc limit 20 offset ?

@@ select_tags.sql

select users.nick, users.url ,strftime('%Y-%m-%dT%H:%M:%SZ',tweets.timestamp,"unixepoch") as time, tweets.tweet
    from tweets join users       using ( user_id )
                join tweets_tags using ( tweet_id )
		join tags        using ( tag_id )
    where
          tags.name like ?
      and case when ? then 1 else is_bot is 0 end
    order by tweets.timestamp desc limit 20 offset ?

@@ select_mentions.sql

select users.nick, users.url ,strftime('%Y-%m-%dT%H:%M:%SZ',tweets.timestamp,"unixepoch") as time, tweets.tweet
    from tweets join mentions using ( tweet_id )
                join users as mentioned on mentions.user_id = mentioned.user_id
	        join users on tweets.user_id = users.user_id
    where ( mentioned.url is ? or mentioned.nick is ? )
      and case when ? then 1 else users.is_bot is 0 end
    order by tweets.timestamp desc limit 20 offset ?
