
use lib "./lib";
use Hardware::Simulator::MIX;

my $mix = new Hardware::Simulator::MIX;
$mix->reset();

while (!$mix->is_halted())
{
	$mix->step();
}
if ($mix->{status} == 1) {
	print "MIX: ", $mix->{message}, "\n";
} else {
	print "MIX ERROR: ", $mix->{message}, "\n";
}

