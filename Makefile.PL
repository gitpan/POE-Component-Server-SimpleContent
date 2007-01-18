use inc::Module::Install;
name 'POE-Component-Server-SimpleContent';
author 'Chris Williams <chris@bingosnet.co.uk>';
license 'perl';
version_from 'lib/POE/Component/Server/SimpleContent.pm';
requires 'POE'    => 0.38;
requires 'Carp' => 0;
requires 'CGI' => 0;
requires 'MIME::Types' => 1.15;
requires 'URI::Escape' => 3.28;
requires 'Filesys::Virtual::Plain' => 0.07;
requires 'HTTP::Request' => 0;
requires 'HTTP::Response' => 0;
WriteAll();