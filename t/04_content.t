# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl 1.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 7;
BEGIN { use_ok('POE::Component::Server::SimpleContent') };

#########################

use POE;
use HTTP::Request;
use HTTP::Response;

my ($content) = POE::Component::Server::SimpleContent->spawn( root_dir => 'static/' );

isa_ok( $content, 'POE::Component::Server::SimpleContent' );

POE::Session->create(
	package_states => [
		'main' => [ qw(_start _timeout DONE) ],
	],
);

$poe_kernel->run();
exit 0;

sub _start {
  $_[HEAP]->{content} = [ qw(200 404 301 403 404) ];

  $content->auto_index( 0 );
  $content->request( HTTP::Request->new( GET => 'http://localhost/' ), HTTP::Response->new() );
  $content->request( HTTP::Request->new( GET => 'http://localhost/blah' ), HTTP::Response->new() );
  $content->request( HTTP::Request->new( GET => 'http://localhost/test' ), HTTP::Response->new() );
  $content->request( HTTP::Request->new( GET => 'http://localhost/test/' ), HTTP::Response->new() );
  $content->request( HTTP::Request->new( GET => 'http://localhost/../t/' ), HTTP::Response->new() );

  $poe_kernel->delay( _timeout => 60 );
  undef;
}

sub _timeout {
  $content->shutdown();
  undef;
}

sub DONE {
  my ($heap) = $_[HEAP];
  my ($code) = shift @{ $heap->{content} };
  my ($response) = $_[ARG0];

  ok( $response->code eq $code, "Test for $code" );

  if ( scalar @{ $heap->{content} } == 0 ) {
	$poe_kernel->delay( _timeout => undef );
	$content->shutdown();
  }
  undef;
}
