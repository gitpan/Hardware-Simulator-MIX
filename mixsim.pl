
use lib "./lib";
use Hardware::Simulator::MIX;

my $mix = new Hardware::Simulator::MIX;
$mix->reset();

$mix->set_word(0 , ['+', 0, 10, 0, 5, 8]); # LDA 10(0:5)
$mix->set_word(1 , ['+', 0,  0, 0, 2, 5]); # HLT
$mix->set_word(10, ['-', 0,  1, 2, 3, 4]);

while (!$mix->is_halted())
{
	$mix->step();
}

$mix->print_all_regs();
