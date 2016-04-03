package App::TwtxtRoster;
use strict;
use warnings;
use Mojo::Base 'Mojolicious';

use Mojo::SQLite;
use Mojo::Date;
use Try::Tiny;
use Mojo::ByteStream 'b';
use Mojo::JSON 'encode_json';
use Regexp::Common;

our $VERSION = '0.01';
$ENV{TZ} = 'UTC';

sub startup {
    my $self = shift;

    $self->moniker('twtxt-roster');

    my $config = $self->plugin(
        config => {
            default => {
                minion_db    => 'sqlite:minion.db',
                registry_db  => 'sqlite:registry.db',
                delay        => 300,
                registration => 0,
            }
        }
    );

    $self->plugin( minion => { SQLite => $config->{minion_db} } );

    $self->types->type( plain => 'text/plain;charset=UTF-8' );

    $self->helper(
        find_new_urls => sub {
            my ( $self, $tweet ) = @_;
            while ( $tweet =~ m{\@<(\w+) (https?://[^>]+)>}g ) {
                my ( $nick, $url ) = ( $1, $2 );
                $self->add_user( $nick, $url );
            }
            return;
        }
    );

    $self->helper(
        add_user => sub {
            my ( $self, $nick, $url ) = @_;
            $url = Mojo::URL->new($url);
            return if $url->scheme !~ /^https?/;

            ## If url scheme is https and there is already an url with the same http address
            ## just update the http address to https
            if ( $url->scheme eq 'https' ) {
                my $http_url = $url->clone->scheme('http');
                return
                  if $self->sql->db->query(
                    'update users set url = ? where url is ?',
                    $url, $http_url )->rows;
            }

            my $https_address = $url->clone->scheme('https');
            my $result        = $self->sql->db->query(
                q{
                   insert into users ( nick, url )
                    select ?,? where not exists
                     (select 1 from users where url in ( ?, ? ))
                 },
                $nick, $url, $url, $https_address
            );
            return if !$result->rows;

            my $id = $result->last_insert_id;
            $self->minion->enqueue( 'update', [$id],
                { delay => $config->{delay} } )
              if defined $id;
            return;
        }
    );

    $self->helper(
        to_date => sub {
            my ( $c, $date ) = @_;
            return if !$date;
            $date =~ s/T(\d\d:\d\d)([Z+-])/T$1:00$2/;
            $date =~ s/([+-]\d\d)(\d\d)/$1:$2/;
            return Mojo::Date->new($date);
        }
    );

    $self->minion->add_task(
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

                $job->app->log->debug("Success $url");

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
                            $db->query(
                                'insert into tweets (user_id,timestamp,tweet)'
                                  . ' values ((select user_id from users where url is ?),?,?)',
                                $url,
                                $time->epoch,
                                substr( $tweet, 0, 1024 )
                            );
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
                            $db->query(
'update users set last_modified = ? where url is ?',
                                $date->epoch, $url
                            );
                        }
                    }
                }

                $job->app->minion->enqueue( 'update', [$id],
                    { delay => $config->{delay} } );

            }
            catch {
                $log->debug("Error: $_");
                $db->query(
'update users set active = 0, last_error = ? where url is ?',
                    $_, $url
                );

            };
            return;
        }
    );

    $self->helper(
        sql => sub {
            state $sql = Mojo::SQLite->new( $config->{registry_db} );
        }
    );

    $self->helper(
        offset => sub {
            my $c = shift;

            my $page = $c->param('page') || 1;
            $page = 1
              if $page <= 0 || $page !~ /^\d+$/;
            $c->stash( page => $page );

            my $offset = ( $page - 1 ) * 20;
            return $offset;
        }
    );

    $self->helper(
        respond_to_api => sub {
            my ( $c, $sql, @bind_values ) = @_;
            $c->stash( template => $c->current_route );
            my $values = $c->sql->db->query( $sql, @bind_values );
            return $c->respond_to(
                plain => sub {
                    $c->render( text =>
                          $values->arrays->map( sub { join( "\t", @$_ ) } )
                          ->join("\n") );
                },
                json => sub {
                    $c->render( json => $values->hashes );
                },
                any => sub {
                    $c->render(
                        template => 'index',
                        tweets   => $values->hashes
                    );
                },
            );
        }
    );

    $self->helper(
        format_tweet => sub {
            my ( $c, $tweet ) = @_;

            $tweet = b($tweet)->xml_escape->to_string;
            $tweet =~ s{\@&lt;(\w+) (https?://.+?)&gt;}{<a href="$2">\@$1</a>}g;

            $tweet =~ s{(?<!&)#(\w+)}
               {  '<a href="'
		. $c->url_for(tags => tag => $1, format => 'html')
		. '">#'.$1.'</a>'}ge;

            my $http_re = $RE{URI}{HTTP}{ -scheme => qr/https?/ }{ -keep => 1 };
            $tweet =~ s{(?<!href=")$http_re}{<a href="$1">$1</a>}g;
            return $tweet;
        }
    );

    my $r = $self->routes;

    my $api =
      $r->under( '/api/:format/' => [ format => [ 'plain', 'json', 'html' ] ] );
    $api->post('/users')->to('users#register');

    # TODO just use a shortcut
    $api->get('/tweets')->to('tweets#get_tweets');
    $api->get('/mentions')->to('tweets#get_mentions');
    $api->get('/tags/:tag')->to('tweets#get_tags')->name('tags');
    $api->get('/users')->to('users#get');

    $r->get('/tweets')->to('tweets#get_tweets');
    $r->get('/mentions')->to('tweets#get_mentions');
    $r->get('/tags/:tag')->to('tweets#get_tags')->name('tags');
    $r->get('/users')->to('users#get');

    $r->get('/')->to('tweets#get_tweets')->name('index');
    $r->websocket('/stream')->to('tweets#stream');
}

1;
