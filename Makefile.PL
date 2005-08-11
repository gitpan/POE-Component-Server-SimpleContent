use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
# Blah!

WriteMakefile(
			  'NAME'	=> 'POE::Component::Server::SimpleContent',
			  'PREREQ_PM' => {
							  'POE'    => 0.31,
							  'Carp' => 0,
							  'CGI' => 0,
							  'MIME::Types' => 1.15,
							  'URI::Escape' => 3.28,
							  'Filesys::Virtual::Plain' => 0.07,
							  'HTTP::Request' => 0,
							  'HTTP::Response' => 0,
							 },
			  'VERSION_FROM' => 'lib/POE/Component/Server/SimpleContent.pm', # finds $VERSION
			  'dist' => { 'COMPRESS' => 'gzip --best' },
			 );
