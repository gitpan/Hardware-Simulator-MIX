#!/usr/bin/perl
# vim:set filetype=perl:

use warnings;
use strict;

use Test::More tests => 4;

use Hardware::Simulator::MIX;

ok(mix_char_code( mix_char(0) ) == 0);
ok(mix_char_code( mix_char(10) ) == 10);
ok(mix_char_code( mix_char(20) ) == 20);
ok(mix_char_code( mix_char(30) ) == 30);

