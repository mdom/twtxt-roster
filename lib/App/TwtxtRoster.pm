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
    $self->plugin('App::TwtxtRoster::Task::Update');

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
		. $c->url_for(tagstag => tag => $1, format => 'html')
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

    $r->add_shortcut(
        with_api => sub {
            my ( $r, $path, $action ) = @_;
            $r->get($path)->to($action);
            $api->get($path)->to($action);
            return $r;
        }
    );

    $r->with_api( '/tweets',    'tweets#get_tweets' );
    $r->with_api( '/mentions',  'tweets#get_mentions' );
    $r->with_api( '/tags/:tag', 'tweets#get_tags' );
    $r->with_api( '/users',     'users#get' );

    $r->get('/')->to('tweets#get_tweets')->name('index');
    $r->websocket('/stream')->to('tweets#stream');
}

1;

__END__

=head1 NAME

twtxt_roster - api and search engine for twtxt

=head1 COPYRIGHT AND LICENSE

Copyright 2015 Mario Domgoergen C<< <mario@domgoergen.com> >>

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program.  If not, see <http://www.gnu.org/licenses/>.
