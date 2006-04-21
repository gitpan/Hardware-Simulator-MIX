#!/usr/bin/perl
# vim:set filetype=perl:

use warnings;
use strict;

use Test::More tests => 2;

use Hardware::Simulator::MIX;

my $mix = Hardware::Simulator::MIX->new;
my @word1 = ('-', 1, 2, 3, 4, 5);
my @word2 = ('+', 0, 0, 1, 1, 2);
$mix->set_word( 0, \@word1);
my @tmp = $mix->get_word(0);
is_deeply(\@word1, \@tmp, "full set/get");

$mix->set_word(0, [0, 0], 1, 2);
@tmp = $mix->get_word(0);
is_deeply(\@tmp, ['-', 0, 0, 3, 4, 5], "partial set/ full get");
