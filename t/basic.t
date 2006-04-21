#!/usr/bin/perl
# vim:set filetype=perl:

use warnings;
use strict;

use Test::More tests => 3;

BEGIN {
	use_ok 'Hardware::Simulator::MIX';
}

ok('Hardware::Simulator::MIX'->can('new'),   'new');
ok('Hardware::Simulator::MIX'->can('reset'), 'reset');


