package App::TwtxtRoster::Controller::Users;
use Mojo::Base 'Mojolicious::Controller';

my $find_users_sql = <<EOF;
  SELECT nick, url, strftime('%Y-%m-%dT%H:%M:%SZ',timestamp,"unixepoch") as time FROM users
    WHERE url LIKE ? OR nick like ? ORDER BY time LIMIT 20 OFFSET ?
EOF

sub get {
    my $c = shift;
    my $query = $c->param('q') || '%';
    $c->stash( template => 'users' );
    return $c->respond_to_api( $find_users_sql, $query, $query, $c->offset );
}

sub register {
    my $c = shift;
    return $c->render( text => 'Registration closed.', status => 403 )
      if !$c->config->{registration};
    my ( $url, $nick ) = ( $c->param('url'), $c->param('nickname') );
    return $c->render( text => 'Oops.', status => 400 )
      if !$url || !$nick;
    $c->add_user( $nick, $url );
    return $c->render( text => 'Ok.', status => 200 );
}

1;
