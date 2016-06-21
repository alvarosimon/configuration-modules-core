#!/usr/bin/perl
# -*- mode: cperl -*-
use strict;
use warnings;
use Test::More;
use Test::Quattor;
use NCM::Component::metaconfig;
use CAF::Object;

use JSON::Any;

$CAF::Object::NoAction = 1;
set_caf_file_close_diff(1);


=pod

=head1 DESCRIPTION

Test that a JSON config file can be generated by this component.

=cut


my $cmp = NCM::Component::metaconfig->new('metaconfig');

my $cfg = {
	   owner => 'root',
	   group => 'root',
	   mode => 0644,
	   contents => {
			foo => 1,
			bar => 2,
			baz => {
				a => [0..3]
				}
			},
	   daemons => {'httpd' => 'restart'},
	   module => "json",
	  };

$cmp->handle_service("/foo/bar", $cfg);

my $fh = get_file("/foo/bar");

isa_ok($fh, "CAF::FileWriter", "Correct class");
my $js = JSON::Any->Load("$fh");
is($js->{foo}, 1, "JSON file correctly created and reread");
is($js->{baz}->{a}->[2], 2, "JSON file correctly created and reread (pt 2)");

done_testing();
