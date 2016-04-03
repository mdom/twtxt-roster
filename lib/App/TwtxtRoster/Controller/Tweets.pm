package App::TwtxtRoster::Controller::Tweets;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::SQLite;
use Mojo::Date;
use Try::Tiny;
use Mojo::ByteStream 'b';
use Mojo::JSON 'encode_json';

my $find_tweets_base = <<EOF;
    from tweets join users on tweets.user_id == users.user_id
    where
          tweet like ?
      and case when ? then 1 else is_bot is 0 end
    order by tweets.timestamp desc limit 20 offset ?
EOF

my $find_tweets_1_0 = <<EOF;
  select "@<"||nick||" "||url||">" as user, strftime('%Y-%m-%dT%H:%M:%SZ',tweets.timestamp,"unixepoch") as time, tweet
  $find_tweets_base
EOF

my $find_tweets_2_0 = <<EOF;
  select nick, url ,strftime('%Y-%m-%dT%H:%M:%SZ',tweets.timestamp,"unixepoch") as time, tweet
  $find_tweets_base
EOF

sub get_tweets {
    my $c         = shift;
    my $query     = $c->param('q') || '%';
    my $show_bots = $c->param('show_bots') || 0;
    return $c->respond_to_api( $find_tweets_2_0, "%$query%", $show_bots,
        $c->offset );
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
    my $c     = shift;
    my $query = $c->param('tag');
    return $c->render( status => 400, text => '`tag` must be provided.' )
      if !$query;
    $c->param( q => "#$query" );
    return $c->get_tweets;
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
