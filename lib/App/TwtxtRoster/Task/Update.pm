package App::TwtxtRoster::Task::Update;
use Mojo::Base 'Mojolicious::Plugin';

use Mojo::Date;
use Try::Tiny;
use Mojo::ByteStream 'b';
use Mojo::JSON 'encode_json';
use Mojo::Loader 'data_section';

sub register {
    my ( $self, $app ) = @_;

    $app->minion->add_task(
        update => sub {
            my ( $job, $id ) = @_;

            my $db  = $job->app->sql->db;
            my $log = $job->app->log;

            my $user =
              $db->query( 'select * from users where user_id is ?', $id )->hash;
            return if not defined $user;
            return if not $user->{active};
            my ( $nick, $url, $last_modified ) =
              @{$user}{qw( nick url last_modified )};

            $job->app->log->debug("Updating $url");

            $last_modified = Mojo::Date->new($last_modified)
              if $last_modified;

            my $params =
              $last_modified
              ? { 'If-Modified-Since' => $last_modified->to_string }
              : {};

            my $tx = $job->app->ua->get( $url, $params );

            try {
                $log->debug("Try $url");
                my $res = $tx->success;
                die $tx->error->{message} if !$res;

                $job->app->log->debug( "Success $url with code " . $res->code );

                if ( $res->code == 301 || $res->code == 307 ) {
                    $db->query( 'delete from users where url is ?', $url );
                    $job->app->add_user( $nick, $res->headers->location );
                    return;
                }
                elsif ( $res->code == 200 ) {
                    my $now = Mojo::Date->new();
                    for my $line ( split( "\n", b( $res->body )->decode ) ) {
                        next if $line =~ m/^\s*$/;
                        my ( $time, $sep, $tweet ) =
                          $line =~ /(.*?)(\s+|#)(.*)/;
                        next if $sep eq '#';

                        $time = $job->app->to_date($time);
                        $job->app->log->debug($tweet);
                        $job->app->log->debug($time);

                        die "Unparsable line $line\n"
                          if !defined $time || !defined $tweet;

                        next if $time->epoch > $now->epoch;

                        try {
                            my $tx       = $db->begin;
                            my $tweet_id = $db->query(
                                data_section( __PACKAGE__, 'insert_tweets.sql'
                                ),
                                $url,
                                $time->epoch,
                                substr( $tweet, 0, 1024 )
                            )->last_insert_id;

                            $job->app->log->debug("Inserted $tweet");

                            for my $tag ( $tweet =~ /#(\w+)/g ) {
                                $db->query(
                                    data_section( __PACKAGE__,
                                        'insert_tags.sql'
                                    ),
                                    $tag
                                );
                                $db->query(
                                    data_section( __PACKAGE__,
                                        'insert_tweets_tags.sql'
                                    ),
                                    $tweet_id,
                                    $tag
                                );
                            }

                            $tx->commit;

                            $job->app->find_new_urls($tweet);
                            $job->app->sql->pubsub->notify(
                                'new_tweet' => encode_json(
                                    {
                                        tweet  => $tweet,
                                        time   => $time->to_datetime,
                                        url    => $url,
                                        nick   => $nick,
                                        is_bot => $user->{is_bot},
                                    }
                                )
                            );
                        };

                    }

                    if ( $res->headers->last_modified ) {
                        my $date =
                          Mojo::Date->new( $res->headers->last_modified );
                        if ( defined $date ) {
                            $db->query( '
				    update users set last_modified = ?
				      where url is ?
				',
                                $date->epoch, $url );
                        }
                    }
                }

                $job->app->minion->enqueue( 'update', [$id],
                    { delay => $app->config->{delay}, attempts => 10 } );

            }
            catch {
                $job->fail;
                $db->query(
                    'update users
			  set last_error = ?
			  where url is ?',
                    $_, $url
                );
                $db->query(
                    'update users
			  set active = 0
			  where url is ?', $url
                ) if $job->info->{state} eq 'failed';

            };
            return;
        }
    );
}

1;

__DATA__

@@ insert_tweets.sql

insert into tweets (
    user_id,
    timestamp,
    tweet
  )
  values (
    (select user_id from users where url is ?),
    ?,
    ?
  )

@@ insert_tags.sql

insert or ignore into tags ( name ) values ( ? )

@@ insert_tweets_tags.sql

insert or ignore into tweets_tags (
    tweet_id,
    tag_id
  )
  values (
    ?,
    (select tag_id from tags where name is ?)
  )
