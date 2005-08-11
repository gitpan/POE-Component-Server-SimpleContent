package POE::Component::Server::SimpleContent;

use Carp;
use strict;
use warnings;
use POE;
use CGI qw(:standard);
use URI::Escape;
use Filesys::Virtual::Plain;
use MIME::Types;
use vars qw($VERSION);

$VERSION = '0.01';

sub spawn {
  my ($package) = shift;
  croak "$package needs an even number of parameters" if @_ & 1;
  my %params = @_;

  foreach my $param ( keys %params ) {
     $params{ lc $param } = delete ( $params{ $param } );
  }

  unless ( $params{root_dir} and -d $params{root_dir} ) {
	die "$package requires a 'root_dir' argument\n";
  }

  my $options = delete ( $params{'options'} );

  my $self = bless \%params, $package;

  $self->{vdir} = Filesys::Virtual::Plain->new( { root_path => $self->{root_dir} } )
	or die "Could not create a Filesys::Virtual::Plain object for $self->{root_dir}\n";

  $self->{mt} = MIME::Types->new();

  $self->{autoindex} = 1 unless ( defined ( $self->{autoindex} ) and $self->{autoindex} == 0 );
  $self->{index_file} = 'index.html' unless ( $self->{index_file} );

  my ($mm);

  eval {
	require File::MMagic;
	$mm = File::MMagic->new();
  };
 
  $self->{mm} = $mm;

  $self->{session_id} = POE::Session->create(
	object_states => [
		$self => { request  => '_request',
			   shutdown => '_shutdown',
		},
		$self => [ qw(_start) ],
	],
	( ( defined ( $options ) and ref ( $options ) eq 'HASH' ) ? ( options => $options ) : () ),
  )->ID();

  return $self; 
}

sub _start {
  my ($kernel,$self) = @_[KERNEL,OBJECT];

  $self->{session_id} = $_[SESSION]->ID();

  if ( $self->{alias} ) {
	$kernel->alias_set( $self->{alias} );
  } else {
	$kernel->refcount_increment( $self->{session_id} => __PACKAGE__ );
  }

  undef;
}

sub request {
  my ($self) = shift;
  $poe_kernel->post( $self->session_id() => 'request' => @_ );
}

sub _request {
  my ($kernel,$self,$request,$response) = @_[KERNEL,OBJECT,ARG0 .. ARG1];
  my ($sender) = $_[SENDER]->ID();

  # Sanity check the $request and $response objects *sigh*
  unless ( $response and $response->isa("HTTP::Response") ) {
	return;
  }
  unless ( $request and $request->isa("HTTP::Request") ) {
	$kernel->call( $sender => 'DONE' => $response );
	return;
  }

  my ($path) = uri_unescape( $request->uri->path );

  SWITCH: {
    if ( $self->{vdir}->test('d', $path) ) {
	if ( $path !~ /\/$/ ) {
	  $path .= '/';
	  $response->header( 'Location' => $path );
	  $response = $self->_generate_301( $path, $response );
	  last SWITCH;
	}
	if ( $self->{auto_index} and not $self->{vdir}->test('e', $path . $self->{index_file} ) ) {
	  $response = $self->_generate_dir_listing( $path, $response );
	  last SWITCH;
	}
	if ( $self->{vdir}->test('e', $path . $self->{index_file} ) ) {
	  $response = $self->_generate_content( $path . $self->{index_file}, $response );
	  last SWITCH;
	}
	$response = $self->_generate_403( $response );
	last SWITCH;
    }
    if ( $self->{vdir}->test('e', $path) ) {
	$response = $self->_generate_content( $path, $response );
	last SWITCH;
    }
    $response = $self->_generate_404( $response );
  }

  $kernel->call( $sender => 'DONE' => $response );
  undef;
}

sub shutdown {
  my ($self) = shift;
  $poe_kernel->post( $self->session_id() => 'shutdown' => @_ );
}

sub _shutdown {
  my ($kernel,$self) = @_[KERNEL,OBJECT];

  if ( $self->{alias} ) {
	$kernel->alias_remove( $_ ) for $kernel->alias_list();
  } else {
	$kernel->refcount_decrement( $self->{session_id} => __PACKAGE__ );
  }
  undef;
}

sub session_id {
  return $_[0]->{session_id};
}

sub autoindex {
  my ($self) = shift;
  my ($value) = shift;

  unless ( defined ( $value ) ) {
	return $self->{autoindex};
  }
  $self->{autoindex} = $value;
}

sub index_file {
  my ($self) = shift;
  my ($value) = shift;

  unless ( defined ( $value ) ) {
	return $self->{index_file};
  }
  $self->{index_file} = $value;
}

sub _generate_404 {
  my ($self) = shift;
  my ($response) = shift || return undef;

  $response->code( 404 );
  $response->content( start_html('404') . h1('Not Found') . end_html );

  return $response;
}

sub _generate_403 {
  my ($self) = shift;
  my ($response) = shift || return undef;

  $response->code( 403 );
  $response->content( start_html('403') . h1('Forbidden') . end_html );

  return $response;
}

sub _generate_301 {
  my ($self) = shift;
  my ($path) = shift || return undef;
  my ($response) = shift || return undef;

  $response->code( 301 );
  $response->content( start_html('301') . h1('Moved Permanently') . '<p>The document has moved <a href="' . $path . '">here</a>.</p>' . end_html );
  return $response;
}

sub _generate_dir_listing {
  my ($self) = shift;
  my ($path) = shift || return undef;
  my ($response) = shift || return undef;
  my ($content) = start_html('Index of ' . $path) . h1('Index of ' . $path) . qq{<HR>\n<UL>\n};

  foreach my $item ( $self->{vdir}->list( $path ) ) {
	next if $item =~ /^\./;
	$content .= qq{<LI><A HREF="$path$item">$item</A></LI>\n};
  }
  
  $content .= qq{</UL>\n} . end_html;
  $response->code( 200 );
  $response->content( $content );
  return $response;
}

sub _generate_content {
  my ($self) = shift;
  my ($path) = shift || return undef;
  my ($response) = shift || return undef;

  my ($mimetype) = $self->{mt}->mimeTypeOf( $path );

  if ( my $fh = $self->{vdir}->open_read( $path ) ) {
	binmode($fh);
	local $/ = undef;
	my $content = <$fh>;
	unless ( $mimetype ) {
	  if ( $self->{mm} ) {
		$mimetype = $self->{mm}->checktype_contents( $content );
	  } else {
		$mimetype = 'application/octet-stream';
	  }
	}
	$response->code( 200 );
	$response->content_type( $mimetype );
	$response->content_ref( \$content );
  } else {
	$response = $self->_generate_404( $response );
  }

  return $response;
}

1;

__END__

=head1 NAME

POE::Component::Server::SimpleContent - The easy way to serve web content with L<POE::Component::Server::SimpleHTTP>.

=head1 SYNOPSIS

  # A simple web server 
  use POE qw(Component::Server::SimpleHTTP Component::Server::SimpleContent);

  my ($content) = POE::Component::Server::SimpleContent->spawn( root_dir => '/blah/blah/path' );

  POE::Component::Server::SimpleHTTP->new(
	ALIAS => 'httpd',
	ADDRESS => '6.6.6.6',
	PORT => 8080,
	HANDLERS => [
		{
		  DIR => '.*',
		  EVENT => 'request',
		  SESSION => $content->session_id(),
		},
	],
  );

  $poe_kernel->run();
  exit 0;

=head1 DESCRIPTION

POE::Component::Server::SimpleContent is a companion L<POE> component to L<POE::Component::Server::SimpleHTTP> ( though it can be used standalone ), that provides a virtualised filesystem for serving web content. It uses L<Filesys::Virtual::Plain> to manage the virtual file system.

As demonstrated in the SYNOPSIS, POE::Component::Server::SimpleContent integrates with L<POE::Component::Server::SimpleHTTP>. General usage involves setting up your own custom handlers *before* a catchall handler which will route HTTP requests to SimpleContent.

The component generates a minimal 404 error page as a response if the requested URL doesn't not exist in the virtual filesystem. It will generate a minimal 403 forbidden page if 'autoindex' is set to 0 and a requested directory doesn't have an 'index_file' 

Directory indexing is supported by default, though don't expect anything really fancy.

=head1 CONSTRUCTOR

=over

=item spawn

Requires one mandatory argument, 'root_dir': the file system path which will become the root of the virtual filesystem. Returns an object on success. Optional arguments are:

 alias      - the POE::Kernel alias to set for the component's session;
 options    - a hashref of POE::Session options to pass to the component's session;
 index_file - the filename that will be used if someone specifies a directory path,
	      default is 'index.html';
 autoindex  - whether directory indexing is performed, default is 1;

Example:

 my ($content) = POE::Component::Server::SimpleContent->spawn(
	root_dir   => '/blah/blah/path',
	options    => { trace => 1 },
	index_file => 'default.htm',
	autoindex  => 0,
 );

=back

=head1 METHODS

=over

=item session_id

Takes no arguments. Returns the L<POE::Session> ID of the component's session.

  my ($session_id) = $content->session_id();

=item shutdown

Takes no arguments, shuts down the component's session.

  $content->shutdown();

=item request

Requires two arguments, a L<HTTP::Request> object and L<HTTP::Response> object. See OUTPUT 
for what is returned by this method.

  $content->request( $request_obj, $response_obj );

=item autoindex

No parameter specified returns whether 'autoindex' is enabled or not. If a true or false value is specified, enables or disables 'autoindex', respectively.

=item index_file

No parameter specified, returns the current setting of 'index_file'. If a parameter is specified, sets 'index_file' to that given value.

=back

=head1 INPUT

These are the events that the component will accept.

=over

=item request

Requires two arguments, a L<HTTP::Request> object and L<HTTP::Response> object. See OUTPUT 
for what is returned by this method.

  $kernel->post( $content->session_id() => request => $request_obj => $response_obj );

=item shutdown

Takes no arguments, shuts down the component's session.

  $kernel->post( $content->session_id() => 'shutdown' );

=back

=head1 OUTPUT

The component returns the following event to the sessions that issued a 'request', either via the
object API or the session API. The event is 'DONE' to maintain compatibility with L<POE::Component::Server::SimpleHTTP>.

=over

=item DONE

ARG0 will be a L<HTTP::Response> object. 

=back

=head1 CAVEATS

This module is designed for serving small content, ie. HTML files and jpegs/png/gifs. There is a good chance that the component might block when atttempting to serve larger content, such as MP3s, etc.

=head1 TODO

Use L<POE::Wheel::Run> to provide full non-blocking content serving.

More comprehensive HTTP error handling, with the ability to specify custom 404 error pages.

More 'fancy' directory listing.

=head1 AUTHOR

Chris 'BinGOs' Williams

=head1 KUDOS

Apocal for writing POE::Component::Server::SimpleHTTP.

Xantus for Filesys::Virtual::Plain

Those cheeky chaps at #PoE @ irc.perl.org for ever helpful suggestions.

=head1 SEE ALSO

L<HTTP::Request>, L<HTTP::Request>, L<POE::Component::Server::SimpleHTTP>, L<POE>.

=cut
