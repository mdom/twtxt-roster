package App::TwtxtRoster::Controller::Tweets;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Loader 'data_section';

sub get_tweets {
    my $c         = shift;
    my $query     = $c->param('q') || '%';
    my $show_bots = $c->param('show_bots') || 0;
    $c->stash( template => 'tweets' );
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
    my $c     = shift;
    my $query = $c->param('url');
    return $c->render( status => 400, text => '`url` must be provided.' )
      if !$query;
    $c->param( q => "\@<_% $query>" );
    return $c->get_tweets;
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

select nick, url ,strftime('%Y-%m-%dT%H:%M:%SZ',tweets.timestamp,"unixepoch") as time, tweet
    from tweets, users using ( user_id )
    where url is ?
    order by tweets.timestamp desc
    limit 20 offset ?

@@ select_tweet_like.sql

select nick, url ,strftime('%Y-%m-%dT%H:%M:%SZ',tweets.timestamp,"unixepoch") as time, tweet
    from tweets join users using ( user_id )
    where
          tweet like ?
      and case when ? then 1 else is_bot is 0 end
    order by tweets.timestamp desc limit 20 offset ?

@@ select_tags.sql

select nick, url ,strftime('%Y-%m-%dT%H:%M:%SZ',tweets.timestamp,"unixepoch") as time, tweet
    from tweets join users       using ( user_id )
                join tweets_tags using ( tweet_id )
		join tags        using ( tag_id )
    where
          tags.name like ?
      and case when ? then 1 else is_bot is 0 end
    order by tweets.timestamp desc limit 20 offset ?
